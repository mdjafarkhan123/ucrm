import { describe, expect, it, vi } from 'vitest';
import {
	buyNumber,
	driveOrder,
	NumberPurchaseError,
	type NumberPurchaseDeps
} from './sms-number-purchase';
import {
	NumberOrderRefusedError,
	type NumberOrder,
	type NumberPurchaseStore,
	type OpenNumberOrderInput
} from './sms-number-purchase-store';
import { TwilioProvisioningError, type TwilioNumberPurchaseClient } from './twilio';
import type { AvailableNumber, NumberRegulation } from './twilio-country-catalog';

const ORG = '11111111-1111-4111-8111-111111111111';
const ACTOR = '22222222-2222-4222-8222-222222222222';
const NUMBER = '+15125550199';
const PN_SID = 'PN' + 'c'.repeat(32);
// Built at run time so secret scanners never see an account-ID-shaped literal.
const FAKE_ACCESS = {
	subaccountSid: ['A', 'C', 'f'.repeat(32)].join(''),
	authToken: ['fake', 'value'].join('-'),
	messagingServiceSid: ['M', 'G', 'f'.repeat(32)].join('')
};
const START = Date.parse('2026-10-22T12:00:00Z');

function stock(overrides: Partial<AvailableNumber> = {}): AvailableNumber {
	return {
		phoneNumber: NUMBER,
		friendlyName: '(512) 555-0199',
		countryCode: 'US',
		numberType: 'local',
		locality: 'Austin',
		region: 'TX',
		postalCode: null,
		capabilities: { sms: true, mms: true, voice: true },
		addressRequirement: 'none',
		beta: false,
		...overrides
	};
}

// An in-memory store that keeps the same money rules as the database functions: hold on open, charge on purchase,
// release on failure, and one claim winner.
function fakeStore(
	options: { balance?: number; price?: number | null; textingOff?: boolean } = {}
) {
	const orders = new Map<string, NumberOrder & { key: string }>();
	const money = { settled: options.balance ?? 1000, reserved: 0, charges: 0 };
	let clock = START;
	const price = options.price === undefined ? 200 : options.price;
	let next = 1;

	const save = (order: NumberOrder & { key: string }, changes: Partial<NumberOrder>) => {
		const updated = { ...order, ...changes, updatedAt: new Date(clock).toISOString() };
		orders.set(order.id, updated);
		return updated;
	};
	const strip = (order: NumberOrder & { key: string }): NumberOrder => {
		const { key: _key, ...rest } = order;
		return rest;
	};

	const store: NumberPurchaseStore = {
		async findOrderByKey(organizationId, key) {
			const found = [...orders.values()].find(
				(o) => o.organizationId === organizationId && o.key === key
			);
			return found ? strip(found) : null;
		},
		async getOrder(organizationId, id) {
			const found = orders.get(id);
			return found && found.organizationId === organizationId ? strip(found) : null;
		},
		async isTextingSwitchedOff() {
			return options.textingOff ?? false;
		},
		async openOrder(input: OpenNumberOrderInput) {
			if (price === null) throw new NumberOrderRefusedError('number_price_missing');
			if (money.settled - money.reserved < price) {
				throw new NumberOrderRefusedError('insufficient_balance');
			}
			money.reserved += price;
			const order = {
				key: input.idempotencyKey,
				id: `order-${next++}`,
				organizationId: input.organizationId,
				phoneNumber: input.phoneNumber,
				countryCode: input.countryCode,
				numberType: input.numberType,
				capabilities: input.capabilities,
				locality: input.locality,
				region: input.region,
				addressRequirement: input.addressRequirement,
				bundleSid: input.bundleSid,
				addressSid: input.addressSid,
				currencyCode: 'USD',
				monthlyMinor: price,
				setupMinor: 0,
				chargeMinor: price,
				state: 'reserved' as const,
				providerPhoneNumberSid: null,
				senderIdentityId: null,
				failureCode: null,
				createdAt: new Date(clock).toISOString(),
				updatedAt: new Date(clock).toISOString(),
				purchasedAt: null
			};
			orders.set(order.id, order);
			return strip(order);
		},
		async claimPurchase(id) {
			const order = orders.get(id)!;
			if (order.state !== 'reserved') return false;
			save(order, { state: 'purchasing' });
			return true;
		},
		async reclaimPurchase(id, staleBefore) {
			const order = orders.get(id)!;
			if (order.state !== 'purchasing' || Date.parse(order.updatedAt) >= staleBefore.getTime()) {
				return false;
			}
			save(order, {});
			return true;
		},
		async recordPurchased(id, sid) {
			const order = orders.get(id)!;
			if (order.state === 'purchased' || order.state === 'completed') return strip(order);
			money.settled -= order.chargeMinor;
			money.reserved -= order.chargeMinor;
			money.charges += 1;
			return strip(
				save(order, {
					state: 'purchased',
					providerPhoneNumberSid: sid,
					purchasedAt: new Date(clock).toISOString()
				})
			);
		},
		async failOrder(id, code) {
			const order = orders.get(id)!;
			if (order.state !== 'reserved' && order.state !== 'purchasing') return strip(order);
			money.reserved -= order.chargeMinor;
			return strip(save(order, { state: 'failed', failureCode: code }));
		},
		async completeOrder(id) {
			const order = orders.get(id)!;
			return strip(save(order, { state: 'completed', senderIdentityId: 'sender-1' }));
		}
	};

	return {
		store,
		money,
		orders,
		advance: (ms: number) => {
			clock += ms;
		},
		now: () => clock
	};
}

function fakeTwilio(overrides: Partial<TwilioNumberPurchaseClient> = {}) {
	const twilio = {
		purchasePhoneNumber: vi.fn<TwilioNumberPurchaseClient['purchasePhoneNumber']>(async () => ({
			phoneNumberSid: PN_SID,
			phoneNumber: NUMBER,
			capabilities: { sms: true, mms: true, voice: true }
		})),
		findOwnedPhoneNumber: vi.fn<TwilioNumberPurchaseClient['findOwnedPhoneNumber']>(
			async () => null
		),
		addPhoneNumberToMessagingService: vi.fn<
			TwilioNumberPurchaseClient['addPhoneNumberToMessagingService']
		>(async () => ({ phoneNumberSid: PN_SID })),
		...overrides
	};
	return twilio;
}

function setup(
	options: {
		balance?: number;
		price?: number | null;
		textingOff?: boolean;
		stock?: AvailableNumber[];
		regulation?: NumberRegulation | null;
		approved?: { bundleSid: string | null; addressSid: string | null } | null;
		twilio?: Partial<TwilioNumberPurchaseClient>;
	} = {}
) {
	const fake = fakeStore(options);
	const twilio = fakeTwilio(options.twilio);
	const deps: NumberPurchaseDeps = {
		store: fake.store,
		catalog: {
			searchNumbers: vi.fn(async () => options.stock ?? [stock()]),
			getRegulation: vi.fn(async () => options.regulation ?? null)
		},
		twilio,
		paperwork: { findApproved: vi.fn(async () => options.approved ?? null) },
		subaccount: vi.fn(async () => FAKE_ACCESS),
		now: fake.now
	};
	return { ...fake, twilio, deps };
}

const input = {
	organizationId: ORG,
	actorId: ACTOR,
	idempotencyKey: 'browser-key-0001',
	phoneNumber: NUMBER,
	countryCode: 'US',
	numberType: 'local' as const
};

async function codeOf(promise: Promise<unknown>) {
	try {
		await promise;
	} catch (error) {
		if (error instanceof NumberPurchaseError) return error.code;
		throw error;
	}
	return 'no error';
}

const rejected = (providerCode: string) =>
	new TwilioProvisioningError('rejected', 400, 'twilio_rejected', false, providerCode);
const timedOut = () => new TwilioProvisioningError('no result', null, 'twilio_unknown', true);

describe('buyNumber', () => {
	it('buys, charges once, joins the Messaging Service and creates the sender', async () => {
		const t = setup();
		const order = await buyNumber(t.deps, input);

		expect(order.state).toBe('completed');
		expect(order.senderIdentityId).toBe('sender-1');
		expect(t.money).toEqual({ settled: 800, reserved: 0, charges: 1 });
		expect(t.twilio.purchasePhoneNumber).toHaveBeenCalledTimes(1);
		expect(t.twilio.addPhoneNumberToMessagingService).toHaveBeenCalledWith(
			expect.objectContaining({ phoneNumberSid: PN_SID })
		);
	});

	it('records the abilities Twilio reports, not what the browser claimed', async () => {
		const t = setup({ stock: [stock({ capabilities: { sms: true, mms: false, voice: true } })] });
		const order = await buyNumber(t.deps, input);
		expect(order.capabilities).toEqual({ sms: true, mms: false, voice: true });
		expect(order.locality).toBe('Austin');
	});

	it('returns the same order on a repeated press without buying again', async () => {
		const t = setup();
		const first = await buyNumber(t.deps, input);
		const second = await buyNumber(t.deps, input);

		expect(second.id).toBe(first.id);
		expect(t.twilio.purchasePhoneNumber).toHaveBeenCalledTimes(1);
		expect(t.money.charges).toBe(1);
	});

	it('releases the money when Twilio says the number was just taken', async () => {
		const t = setup({
			twilio: {
				purchasePhoneNumber: vi.fn(async () => {
					throw rejected('21422');
				})
			}
		});
		const order = await buyNumber(t.deps, input);

		expect(order.state).toBe('failed');
		expect(order.failureCode).toBe('number_unavailable');
		expect(t.money).toEqual({ settled: 1000, reserved: 0, charges: 0 });
		expect(t.twilio.addPhoneNumberToMessagingService).not.toHaveBeenCalled();
	});

	it('names a paperwork refusal from Twilio', async () => {
		const t = setup({
			twilio: {
				purchasePhoneNumber: vi.fn(async () => {
					throw rejected('21649');
				})
			}
		});
		expect((await buyNumber(t.deps, input)).failureCode).toBe('paperwork_required');
	});

	it('keeps the order waiting when Twilio does not answer, then reconciles without a second purchase', async () => {
		const purchase = vi
			.fn<TwilioNumberPurchaseClient['purchasePhoneNumber']>()
			.mockRejectedValueOnce(timedOut());
		const t = setup({ twilio: { purchasePhoneNumber: purchase } });

		expect(await codeOf(buyNumber(t.deps, input))).toBe('purchase_unconfirmed');
		expect(t.money).toEqual({ settled: 1000, reserved: 200, charges: 0 });

		// Asking again straight away does not start a second purchase while the first may still be in flight.
		expect(await codeOf(buyNumber(t.deps, input))).toBe('purchase_unconfirmed');
		expect(purchase).toHaveBeenCalledTimes(1);

		// A minute later, Twilio shows the first call did buy it.
		t.advance(61_000);
		vi.mocked(t.twilio.findOwnedPhoneNumber).mockResolvedValueOnce({
			phoneNumberSid: PN_SID,
			phoneNumber: NUMBER,
			capabilities: { sms: true, mms: true, voice: true }
		});
		const order = await buyNumber(t.deps, input);

		expect(order.state).toBe('completed');
		expect(purchase).toHaveBeenCalledTimes(1);
		expect(t.money).toEqual({ settled: 800, reserved: 0, charges: 1 });
	});

	it('buys on a later retry when the interrupted call never reached Twilio', async () => {
		const purchase = vi
			.fn<TwilioNumberPurchaseClient['purchasePhoneNumber']>()
			.mockRejectedValueOnce(timedOut())
			.mockResolvedValueOnce({
				phoneNumberSid: PN_SID,
				phoneNumber: NUMBER,
				capabilities: { sms: true, mms: true, voice: true }
			});
		const t = setup({ twilio: { purchasePhoneNumber: purchase } });

		await codeOf(buyNumber(t.deps, input));
		t.advance(61_000);
		const order = await buyNumber(t.deps, input);

		expect(order.state).toBe('completed');
		expect(purchase).toHaveBeenCalledTimes(2);
		expect(t.money.charges).toBe(1);
	});

	it('keeps a number the interrupted call bought even when the retry hears "not available"', async () => {
		const purchase = vi
			.fn<TwilioNumberPurchaseClient['purchasePhoneNumber']>()
			.mockRejectedValueOnce(timedOut())
			.mockRejectedValueOnce(rejected('21422'));
		const t = setup({ twilio: { purchasePhoneNumber: purchase } });

		await codeOf(buyNumber(t.deps, input));
		t.advance(61_000);
		vi.mocked(t.twilio.findOwnedPhoneNumber).mockResolvedValueOnce(null).mockResolvedValueOnce({
			phoneNumberSid: PN_SID,
			phoneNumber: NUMBER,
			capabilities: { sms: true, mms: true, voice: true }
		});
		const order = await buyNumber(t.deps, input);

		expect(order.state).toBe('completed');
		expect(t.money.charges).toBe(1);
	});

	it('continues from another request that won the purchase claim', async () => {
		const t = setup();
		const opened = await t.store.openOrder({
			...input,
			capabilities: { sms: true, mms: true, voice: true },
			locality: null,
			region: null,
			addressRequirement: 'none',
			bundleSid: null,
			addressSid: null
		});
		await t.store.claimPurchase(opened.id);

		expect(await codeOf(driveOrder(t.deps, opened))).toBe('purchase_unconfirmed');
		expect(t.twilio.purchasePhoneNumber).not.toHaveBeenCalled();
	});

	it('finishes joining the number on a retry when that step failed after paying', async () => {
		const attach = vi
			.fn<TwilioNumberPurchaseClient['addPhoneNumberToMessagingService']>()
			.mockRejectedValueOnce(timedOut())
			.mockResolvedValueOnce({ phoneNumberSid: PN_SID });
		const t = setup({ twilio: { addPhoneNumberToMessagingService: attach } });

		expect(await codeOf(buyNumber(t.deps, input))).toBe('setup_unfinished');
		const order = await buyNumber(t.deps, input);

		expect(order.state).toBe('completed');
		expect(t.twilio.purchasePhoneNumber).toHaveBeenCalledTimes(1);
		expect(t.money.charges).toBe(1);
	});

	it('refuses before holding money when the number is gone or cannot text', async () => {
		const gone = setup({ stock: [] });
		expect(await codeOf(buyNumber(gone.deps, input))).toBe('number_unavailable');

		const voiceOnly = setup({
			stock: [stock({ capabilities: { sms: false, mms: false, voice: true } })]
		});
		expect(await codeOf(buyNumber(voiceOnly.deps, input))).toBe('number_cannot_text');
		expect(voiceOnly.money.reserved).toBe(0);
	});

	it('refuses when paperwork is needed and none is approved', async () => {
		const regulation = { regulationSid: 'RN1' } as NumberRegulation;
		const t = setup({ regulation });
		expect(await codeOf(buyNumber(t.deps, input))).toBe('paperwork_required');
		expect(t.money.reserved).toBe(0);

		const address = setup({ stock: [stock({ addressRequirement: 'local' })] });
		expect(await codeOf(buyNumber(address.deps, input))).toBe('paperwork_required');
	});

	it('passes approved paperwork to Twilio', async () => {
		const bundleSid = 'BU' + 'd'.repeat(32);
		const t = setup({
			regulation: { regulationSid: 'RN1' } as NumberRegulation,
			approved: { bundleSid, addressSid: null }
		});
		await buyNumber(t.deps, input);
		expect(t.twilio.purchasePhoneNumber).toHaveBeenCalledWith(
			expect.objectContaining({ bundleSid, addressSid: null })
		);
	});

	it('explains texting switched off, a missing price and too little balance', async () => {
		expect(await codeOf(buyNumber(setup({ textingOff: true }).deps, input))).toBe('texting_off');
		expect(await codeOf(buyNumber(setup({ price: null }).deps, input))).toBe(
			'number_price_missing'
		);
		expect(await codeOf(buyNumber(setup({ balance: 100 }).deps, input))).toBe(
			'insufficient_balance'
		);
	});

	it('reports the phone company being unreachable while checking stock', async () => {
		const t = setup();
		const { TwilioCatalogError } = await import('./twilio-country-catalog');
		t.deps.catalog.searchNumbers = vi.fn(async () => {
			throw new TwilioCatalogError('down', 503, 'twilio_unavailable', true);
		});
		expect(await codeOf(buyNumber(t.deps, input))).toBe('provider_unavailable');
	});
});
