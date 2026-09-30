import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { PATCH } from './[offerId]/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const offerId = '323e4567-e89b-12d3-a456-426614174000';
const packageId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '423e4567-e89b-12d3-a456-426614174000';

// The $149 launch offer from the plan: half off the first three months, for new customers.
function terms(overrides: Record<string, unknown> = {}) {
	return {
		name: 'Launch half price',
		apply_mode: 'automatic',
		code: null,
		discount_kind: 'percent',
		percent_off: 50,
		amount_off_usd_cents: null,
		applies_to_monthly: true,
		applies_to_yearly: false,
		monthly_periods: 3,
		customer_eligibility: 'new',
		claim_starts_at: '2026-10-01T00:00:00Z',
		claim_ends_at: null,
		redemption_cap: null,
		package_ids: [packageId],
		...overrides
	};
}

function request(method: string, body?: unknown) {
	return {
		params: { offerId },
		request: new Request(`http://localhost/api/jafar/package-offers/${offerId}`, {
			method,
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		cookies: {}
	};
}

const listEvent = () => request('GET') as unknown as Parameters<typeof GET>[0];
const createEvent = (body: unknown) =>
	request('POST', body) as unknown as Parameters<typeof POST>[0];
const changeEvent = (body: unknown) =>
	request('PATCH', body) as unknown as Parameters<typeof PATCH>[0];

function client(result: { data: unknown; error: { code: string; message: string } | null }) {
	const rpc = vi.fn(() => Promise.resolve(result));
	mockedClient.mockReturnValue({ rpc } as never);
	return rpc;
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 's' } as never);
});

describe('listing offers', () => {
	it('refuses anyone who is not the platform owner', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const rpc = client({ data: [], error: null });
		expect((await GET(listEvent())).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('returns every offer without caching', async () => {
		client({ data: [{ id: offerId }], error: null });
		const response = await GET(listEvent());
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({ offers: [{ id: offerId }] });
	});
});

describe('creating an offer', () => {
	it('refuses anyone who is not the platform owner', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const rpc = client({ data: null, error: null });
		const response = await POST(createEvent({ idempotency_key: idempotencyKey, terms: terms() }));
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves a new offer at revision 0 and sends unused fields as null', async () => {
		const rpc = client({ data: { applied: true, offer_id: offerId }, error: null });
		const response = await POST(
			createEvent({
				idempotency_key: idempotencyKey,
				// A leftover amount and code from switching the form back must not be stored.
				terms: terms({ amount_off_usd_cents: 5000, code: 'LEFTOVER' })
			})
		);
		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith(
			'save_package_offer',
			expect.objectContaining({
				offer_id: null,
				expected_revision: 0,
				code: null,
				percent_off: 50,
				amount_off_usd_cents: null,
				monthly_periods: 3,
				actor_owner_email: 'owner@example.com',
				idempotency_key: idempotencyKey
			})
		);
	});

	it('stores a typed code in capitals', async () => {
		const rpc = client({ data: { applied: true }, error: null });
		await POST(
			createEvent({
				idempotency_key: idempotencyKey,
				terms: terms({ apply_mode: 'code', code: ' launch-50 ' })
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'save_package_offer',
			expect.objectContaining({ code: 'LAUNCH-50' })
		);
	});

	it.each([
		['a code offer without a code', { apply_mode: 'code', code: '' }, 'code'],
		['a percentage over 100', { percent_off: 101 }, 'percent_off'],
		['monthly billing with no month count', { monthly_periods: null }, 'monthly_periods'],
		['no billing interval', { applies_to_monthly: false }, 'applies_to_monthly'],
		['no package', { package_ids: [] }, 'package_ids'],
		[
			'a last claim day before the first',
			{ claim_ends_at: '2026-09-01T00:00:00Z' },
			'claim_ends_at'
		]
	])('rejects %s before touching the database', async (_label, change, field) => {
		const rpc = client({ data: null, error: null });
		const response = await POST(
			createEvent({ idempotency_key: idempotencyKey, terms: terms(change) })
		);
		expect(response.status).toBe(422);
		const body = (await response.json()) as { field_errors: Record<string, unknown> };
		expect(Object.keys(body.field_errors).some((key) => key.endsWith(field))).toBe(true);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('returns a refused rule, such as a code already in use, as 409', async () => {
		client({ data: null, error: { code: '23505', message: 'That code is already used.' } });
		const response = await POST(createEvent({ idempotency_key: idempotencyKey, terms: terms() }));
		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'That code is already used.' });
	});
});

describe('changing an offer', () => {
	it('refuses anyone who is not the platform owner', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const rpc = client({ data: null, error: null });
		expect((await PATCH(changeEvent({ action: 'archive' }))).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves at the revision Jafar loaded', async () => {
		const rpc = client({ data: { applied: true }, error: null });
		const response = await PATCH(
			changeEvent({ action: 'save', expected_revision: 3, terms: terms() })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'save_package_offer',
			expect.objectContaining({ offer_id: offerId, expected_revision: 3 })
		);
	});

	it('tells Jafar when someone saved the offer after he opened it', async () => {
		client({ data: null, error: { code: 'P0409', message: 'The offer changed.' } });
		const response = await PATCH(
			changeEvent({ action: 'save', expected_revision: 3, terms: terms() })
		);
		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'The offer changed.', reason: 'stale' });
	});

	it('archives and restores through one command', async () => {
		const rpc = client({ data: { applied: true }, error: null });
		await PATCH(changeEvent({ action: 'archive' }));
		await PATCH(changeEvent({ action: 'restore' }));
		expect(rpc).toHaveBeenNthCalledWith(1, 'set_package_offer_archived', {
			offer_id: offerId,
			archived: true,
			actor_owner_email: 'owner@example.com'
		});
		expect(rpc).toHaveBeenNthCalledWith(2, 'set_package_offer_archived', {
			offer_id: offerId,
			archived: false,
			actor_owner_email: 'owner@example.com'
		});
	});

	it('returns 404 for an offer that is gone', async () => {
		client({ data: null, error: { code: '23503', message: 'Offer was not found.' } });
		expect((await PATCH(changeEvent({ action: 'archive' }))).status).toBe(404);
	});

	it('rejects an unknown action before touching the database', async () => {
		const rpc = client({ data: null, error: null });
		expect((await PATCH(changeEvent({ action: 'delete' }))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});
