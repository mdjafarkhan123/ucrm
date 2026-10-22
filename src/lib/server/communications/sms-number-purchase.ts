import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getSmsCountryCatalog, type SmsCountryCatalog } from './sms-country-catalog';
import { createSupabaseNumberPaperworkStore } from './sms-number-paperwork-store';
import {
	createSupabaseNumberPurchaseStore,
	NumberOrderRefusedError,
	type NumberOrder,
	type NumberPurchaseStore
} from './sms-number-purchase-store';
import {
	createTwilioNumberPurchaseClient,
	TwilioProvisioningError,
	type TwilioNumberPurchaseClient
} from './twilio';
import {
	TwilioCatalogError,
	type AddressRequirement,
	type NumberType
} from './twilio-country-catalog';
import {
	createTwilioProvisioningDeps,
	getSubaccountAccess,
	provisionTwilioForOrganization,
	type SubaccountAccess
} from './twilio-provisioning';
import { getTwilioInboundWebhookUrl, getTwilioStatusWebhookUrl } from './twilio-webhook';

// Buying a texting number (Stage 10 Part 2, docs/global-sms-behavior-contract.md), the GoHighLevel way: the business
// picks a number, sees the price, buys. Uplift does the Twilio work in the business's own subaccount.
//
// The order is a resumable saga keyed by the browser's idempotency key:
//   1. check the number is still in stock and can text, and that any paperwork Twilio needs is approved;
//   2. open the order, holding the first charge on the bought balance;
//   3. mark it purchasing, then ask Twilio to buy;
//   4. on Twilio's confirmation, charge and record the number; on a definite refusal, release the hold;
//   5. join the number to the business's Messaging Service and create its sender (pending until readiness).
// Twilio offers no idempotency key for a purchase, so an order left "purchasing" by a dropped connection is
// reconciled by asking Twilio whether the subaccount already owns the number before it ever buys again. A double
// press or a retry reaches the same order, so a business can never be charged twice or get two numbers.

export type NumberPurchaseErrorCode =
	| 'texting_off'
	| 'number_unavailable'
	| 'number_cannot_text'
	| 'number_price_missing'
	| 'insufficient_balance'
	| 'number_being_bought'
	| 'paperwork_required'
	| 'provider_unavailable'
	| 'purchase_unconfirmed'
	| 'setup_unfinished'
	| 'twilio_setup_needs_review';

export class NumberPurchaseError extends Error {
	constructor(
		public readonly code: NumberPurchaseErrorCode,
		message: string,
		public readonly orderId: string | null = null
	) {
		super(message);
		this.name = 'NumberPurchaseError';
	}
}

export type ApprovedPaperwork = { bundleSid: string | null; addressSid: string | null };

/** Part 3's approved paperwork for a country and number kind; null when none is approved yet. */
export type NumberPaperworkPort = {
	findApproved(input: {
		organizationId: string;
		countryCode: string;
		numberType: NumberType;
		addressRequirement: AddressRequirement;
	}): Promise<ApprovedPaperwork | null>;
};

export type NumberPurchaseDeps = {
	store: NumberPurchaseStore;
	catalog: Pick<SmsCountryCatalog, 'searchNumbers' | 'getRegulation'>;
	twilio: TwilioNumberPurchaseClient;
	paperwork: NumberPaperworkPort;
	/** The business's ready subaccount, setting one up first when it has none. */
	subaccount(organizationId: string): Promise<SubaccountAccess>;
	now?: () => number;
};

export type BuyNumberInput = {
	organizationId: string;
	actorId: string;
	idempotencyKey: string;
	phoneNumber: string;
	countryCode: string;
	numberType: NumberType;
};

// Twilio's definite purchase refusals that mean something to the business. Anything else is recorded as a plain
// refusal. https://www.twilio.com/docs/api/errors (21422, 21649, 21631, 21615, 21650, 21651).
const REFUSAL_CODES: Record<string, string> = {
	'21422': 'number_unavailable',
	'21649': 'paperwork_required',
	'21631': 'paperwork_required',
	'21615': 'paperwork_required',
	'21650': 'paperwork_required',
	'21651': 'paperwork_required'
};

export async function buyNumber(
	deps: NumberPurchaseDeps,
	input: BuyNumberInput
): Promise<NumberOrder> {
	const existing = await deps.store.findOrderByKey(input.organizationId, input.idempotencyKey);
	if (existing) return driveOrder(deps, existing);

	if (await deps.store.isTextingSwitchedOff(input.organizationId)) {
		throw new NumberPurchaseError('texting_off', 'Texting is switched off for this business.');
	}

	const stock = await findInStock(deps, input);
	if (!stock.capabilities.sms) {
		throw new NumberPurchaseError('number_cannot_text', 'This number cannot send texts.');
	}

	const paperwork = await requiredPaperwork(deps, input, stock.addressRequirement);

	let order: NumberOrder;
	try {
		order = await deps.store.openOrder({
			organizationId: input.organizationId,
			actorId: input.actorId,
			idempotencyKey: input.idempotencyKey,
			phoneNumber: stock.phoneNumber,
			countryCode: input.countryCode,
			numberType: input.numberType,
			capabilities: stock.capabilities,
			locality: stock.locality,
			region: stock.region,
			addressRequirement: stock.addressRequirement,
			bundleSid: paperwork.bundleSid,
			addressSid: paperwork.addressSid
		});
	} catch (error) {
		if (error instanceof NumberOrderRefusedError) throw refusal(error.code);
		throw error;
	}
	return driveOrder(deps, order);
}

// A Twilio call ends within its 15-second timeout, so an order still "purchasing" a minute later is certainly not
// being bought by anyone; only then may a retry reconcile it. A younger one belongs to a request still in flight.
const PURCHASE_STALE_MS = 60_000;

/** Carry an existing order as far as it can go now. Safe to call repeatedly and concurrently. */
export async function driveOrder(
	deps: NumberPurchaseDeps,
	initial: NumberOrder
): Promise<NumberOrder> {
	let order = initial;
	if (order.state === 'completed' || order.state === 'failed') return order;

	const access = await deps.subaccount(order.organizationId);

	if (order.state === 'reserved') {
		if (!(await deps.store.claimPurchase(order.id))) {
			// Another request claimed it a moment ago: continue from where that one has got to.
			const current = await deps.store.getOrder(order.organizationId, order.id);
			if (!current) throw new Error('A number order disappeared while being bought.');
			return driveOrder(deps, current);
		}
		order = await purchase(deps, order, access, false);
	} else if (order.state === 'purchasing') {
		const staleBefore = new Date((deps.now ?? Date.now)() - PURCHASE_STALE_MS);
		const inFlight = Date.parse(order.updatedAt) >= staleBefore.getTime();
		if (inFlight || !(await deps.store.reclaimPurchase(order.id, staleBefore))) {
			throw new NumberPurchaseError(
				'purchase_unconfirmed',
				'Twilio did not confirm the purchase yet.',
				order.id
			);
		}
		order = await purchase(deps, order, access, true);
	}

	if (order.state === 'failed') return order;
	return attach(deps, order, access);
}

async function purchase(
	deps: NumberPurchaseDeps,
	order: NumberOrder,
	access: SubaccountAccess,
	resuming: boolean
): Promise<NumberOrder> {
	if (resuming) {
		const owned = await ownedNumber(deps, order, access);
		if (owned) return deps.store.recordPurchased(order.id, owned);
	}

	let phoneNumberSid: string;
	try {
		const bought = await deps.twilio.purchasePhoneNumber({
			subaccountSid: access.subaccountSid,
			subaccountAuthToken: access.authToken,
			phoneNumber: order.phoneNumber,
			friendlyName: `ucrm-order-${order.id}`,
			bundleSid: order.bundleSid,
			addressSid: order.addressSid
		});
		phoneNumberSid = bought.phoneNumberSid;
	} catch (error) {
		if (error instanceof TwilioProvisioningError && !error.retryable) {
			// A resumed order may have been bought by the earlier, interrupted call after all (Twilio then says the
			// number is no longer available). Look once more before releasing the money.
			if (resuming) {
				const owned = await ownedNumber(deps, order, access);
				if (owned) return deps.store.recordPurchased(order.id, owned);
			}
			const code = (error.providerCode && REFUSAL_CODES[error.providerCode]) ?? 'twilio_rejected';
			return deps.store.failOrder(order.id, code);
		}
		throw new NumberPurchaseError(
			'purchase_unconfirmed',
			'Twilio did not confirm the purchase yet.',
			order.id
		);
	}
	return deps.store.recordPurchased(order.id, phoneNumberSid);
}

async function ownedNumber(
	deps: NumberPurchaseDeps,
	order: NumberOrder,
	access: SubaccountAccess
): Promise<string | null> {
	try {
		const owned = await deps.twilio.findOwnedPhoneNumber({
			subaccountSid: access.subaccountSid,
			subaccountAuthToken: access.authToken,
			phoneNumber: order.phoneNumber
		});
		return owned?.phoneNumberSid ?? null;
	} catch {
		throw new NumberPurchaseError(
			'purchase_unconfirmed',
			'Twilio did not confirm the purchase yet.',
			order.id
		);
	}
}

async function attach(
	deps: NumberPurchaseDeps,
	order: NumberOrder,
	access: SubaccountAccess
): Promise<NumberOrder> {
	if (!order.providerPhoneNumberSid) {
		throw new NumberPurchaseError('setup_unfinished', 'The number has no Twilio ID yet.', order.id);
	}
	try {
		await deps.twilio.addPhoneNumberToMessagingService({
			subaccountSid: access.subaccountSid,
			subaccountAuthToken: access.authToken,
			messagingServiceSid: access.messagingServiceSid,
			phoneNumberSid: order.providerPhoneNumberSid
		});
	} catch {
		// The number is bought and paid for; only joining it to texting is left, and the next try finishes it.
		throw new NumberPurchaseError(
			'setup_unfinished',
			'The number is bought; finishing its texting setup.',
			order.id
		);
	}
	return deps.store.completeOrder(order.id);
}

type InStockNumber = {
	phoneNumber: string;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	addressRequirement: AddressRequirement;
	locality: string | null;
	region: string | null;
};

// Re-read the number from Twilio's live stock rather than trusting what the browser sent: its abilities and
// address rule decide what the business pays for and whether paperwork is needed.
async function findInStock(
	deps: NumberPurchaseDeps,
	input: BuyNumberInput
): Promise<InStockNumber> {
	const digits = input.phoneNumber.replace(/\D/g, '');
	let rows;
	try {
		rows = await deps.catalog.searchNumbers({
			countryCode: input.countryCode,
			numberType: input.numberType,
			contains: digits.slice(-8),
			limit: 20
		});
	} catch (error) {
		throw providerUnavailable(error);
	}
	const match = rows.find((row) => row.phoneNumber === input.phoneNumber);
	if (!match) {
		throw new NumberPurchaseError('number_unavailable', 'That number is no longer available.');
	}
	return {
		phoneNumber: match.phoneNumber,
		capabilities: match.capabilities,
		addressRequirement: match.addressRequirement,
		locality: match.locality,
		region: match.region
	};
}

async function requiredPaperwork(
	deps: NumberPurchaseDeps,
	input: BuyNumberInput,
	addressRequirement: AddressRequirement
): Promise<ApprovedPaperwork> {
	let regulation;
	try {
		regulation = await deps.catalog.getRegulation({
			countryCode: input.countryCode,
			numberType: input.numberType,
			endUserType: 'business'
		});
	} catch (error) {
		throw providerUnavailable(error);
	}
	const needsBundle = regulation !== null;
	const needsAddress = addressRequirement !== 'none';
	if (!needsBundle && !needsAddress) return { bundleSid: null, addressSid: null };

	const approved = await deps.paperwork.findApproved({
		organizationId: input.organizationId,
		countryCode: input.countryCode,
		numberType: input.numberType,
		addressRequirement
	});
	if (!approved || (needsBundle && !approved.bundleSid) || (needsAddress && !approved.addressSid)) {
		throw new NumberPurchaseError(
			'paperwork_required',
			'This country needs approved paperwork before a number can be bought.'
		);
	}
	return approved;
}

function providerUnavailable(error: unknown): NumberPurchaseError {
	if (error instanceof TwilioCatalogError || error instanceof TwilioProvisioningError) {
		return new NumberPurchaseError(
			'provider_unavailable',
			'The phone company could not be reached.'
		);
	}
	throw error;
}

function refusal(code: string): NumberPurchaseError {
	switch (code) {
		case 'insufficient_balance':
			return new NumberPurchaseError(code, 'There is not enough balance to buy this number.');
		case 'number_price_missing':
			return new NumberPurchaseError(code, 'This kind of number has no price yet.');
		case 'number_cannot_text':
			return new NumberPurchaseError(code, 'This number cannot send texts.');
		case 'number_being_bought':
			return new NumberPurchaseError(code, 'Someone else is buying this number right now.');
		default:
			throw new Error(`Unexpected number order refusal: ${code}`);
	}
}

/** Wire the live store, catalog, Twilio adapter and subaccount setup. */
export function createNumberPurchaseDeps(): NumberPurchaseDeps {
	const client = getOwnerSupabaseClient();
	return {
		store: createSupabaseNumberPurchaseStore(client),
		catalog: getSmsCountryCatalog(),
		twilio: createTwilioNumberPurchaseClient(createTwilioProvisioningDeps().twilio),
		paperwork: createSupabaseNumberPaperworkStore(client),
		subaccount: ensureTwilioSubaccount
	};
}

/** The business's Twilio subaccount, set up first when it has none (its first number or its first paperwork). */
export async function ensureTwilioSubaccount(organizationId: string): Promise<SubaccountAccess> {
	const provisioning = createTwilioProvisioningDeps();
	const ready = await getSubaccountAccess(provisioning, organizationId);
	if (ready) return ready;
	try {
		await provisionTwilioForOrganization(provisioning, {
			organizationId,
			inboundRequestUrl: getTwilioInboundWebhookUrl(),
			statusCallback: getTwilioStatusWebhookUrl()
		});
	} catch (error) {
		if (error instanceof TwilioProvisioningError && error.retryable) {
			throw new NumberPurchaseError(
				'provider_unavailable',
				'The phone company could not be reached.'
			);
		}
		throw new NumberPurchaseError(
			'twilio_setup_needs_review',
			'Uplift needs to finish this business’s texting account.'
		);
	}
	const access = await getSubaccountAccess(provisioning, organizationId);
	if (!access) {
		throw new NumberPurchaseError(
			'twilio_setup_needs_review',
			'Uplift needs to finish this business’s texting account.'
		);
	}
	return access;
}
