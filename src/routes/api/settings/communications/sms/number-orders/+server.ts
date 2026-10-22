import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import {
	buyNumber,
	createNumberPurchaseDeps,
	NumberPurchaseError,
	type NumberPurchaseDeps,
	type NumberPurchaseErrorCode
} from '$lib/server/communications/sms-number-purchase';
import type { NumberOrder } from '$lib/server/communications/sms-number-purchase-store';
import {
	smsNumberOrderSchema,
	smsSettingsFieldErrors
} from '$lib/server/validation/communications-sms-settings.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Plain words for each refusal, shown in the Add number pop-up.
const MESSAGES: Record<NumberPurchaseErrorCode | 'twilio_rejected', string> = {
	texting_off: 'Texting is switched off for your business. Contact Uplift to turn it on.',
	number_unavailable: 'Someone else just took that number. Choose another one.',
	number_cannot_text: 'That number can’t send texts. Choose another one.',
	number_price_missing: 'Uplift hasn’t set a price for this kind of number yet.',
	insufficient_balance: 'There isn’t enough balance to buy this number. Add credit first.',
	number_being_bought: 'Someone else is buying that number right now. Choose another one.',
	paperwork_required: 'This country needs approved paperwork before you can buy a number there.',
	provider_unavailable:
		'We couldn’t reach the phone company. Nothing was bought. Try again in a minute.',
	purchase_unconfirmed: 'We’re checking with the phone company whether the number is yours.',
	setup_unfinished: 'Your number is bought. We’re finishing its texting setup.',
	twilio_setup_needs_review: 'Uplift needs to finish your texting account first. We’ve been told.',
	twilio_rejected: 'The phone company refused this number. Nothing was charged. Choose another one.'
};

// Statuses: a refusal the business can act on is 409; "still checking" outcomes are 202 with the order so the
// pop-up can ask again with the same key; the phone company being unreachable is 503.
const STATUS: Partial<Record<NumberPurchaseErrorCode, number>> = {
	provider_unavailable: 503,
	purchase_unconfirmed: 202,
	setup_unfinished: 202,
	twilio_setup_needs_review: 503
};

function safeOrder(order: NumberOrder) {
	return {
		id: order.id,
		state: order.state,
		phone_number: order.phoneNumber,
		country_code: order.countryCode,
		number_type: order.numberType,
		locality: order.locality,
		region: order.region,
		capabilities: order.capabilities,
		monthly_minor: order.monthlyMinor,
		setup_minor: order.setupMinor,
		charge_minor: order.chargeMinor,
		currency_code: order.currencyCode,
		sender_identity_id: order.senderIdentityId,
		failure_code: order.failureCode,
		failure_message: order.failureCode
			? (MESSAGES[order.failureCode as keyof typeof MESSAGES] ?? MESSAGES.twilio_rejected)
			: null
	};
}

// Buy a number. Sending the same idempotency key again (a double press, a retry, or a "Checking…" poll after a
// dropped connection) continues the same order and never buys or charges twice.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = smsNumberOrderSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the number.', field_errors: smsSettingsFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	const organizationId = check.auth.organization.id;
	let deps: NumberPurchaseDeps | null = null;
	try {
		deps = createNumberPurchaseDeps();
		const order = await buyNumber(deps, {
			organizationId,
			actorId: check.auth.user.id,
			idempotencyKey: parsed.data.idempotency_key,
			phoneNumber: parsed.data.phone_number,
			countryCode: parsed.data.country_code,
			numberType: parsed.data.number_type
		});
		return json({ order: safeOrder(order) }, { headers: noStore });
	} catch (error) {
		if (error instanceof NumberPurchaseError) {
			const order =
				error.orderId && deps
					? await deps.store.getOrder(organizationId, error.orderId).catch(() => null)
					: null;
			return json(
				{
					error: MESSAGES[error.code],
					code: error.code,
					order: order ? safeOrder(order) : null
				},
				{ status: STATUS[error.code] ?? 409, headers: noStore }
			);
		}
		console.error('Could not buy the number.', error);
		return json(
			{ error: 'Something went wrong. Try again; you will never be charged twice.' },
			{ status: 500, headers: noStore }
		);
	}
};
