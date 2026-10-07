import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as GET_COLUMN, POST as START } from './+server';
import { PATCH as MOVE } from './[id]/+server';
import { POST as SHARE } from './[id]/pricing/+server';
import { POST as LOSE } from './[id]/lost/+server';
import { PATCH as SET_TERMS } from './[id]/terms/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadPublicPackages } from '$lib/server/packages/public-packages';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	isOwnerEmail: (email: string) => email === 'owner@example.com'
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/packages/public-packages', () => ({ loadPublicPackages: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedPackages = vi.mocked(loadPublicPackages);

const DEAL_ID = '6f1c2a5e-8b8e-4f4e-9d3c-1a2b3c4d5e6f';
const BUSINESS_ID = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const STEP = { text: 'Call with Acme', due_on: '2026-10-08' };

function signedIn() {
	mockedOwnerSession.mockResolvedValue({
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		access: null,
		memberId: null,
		name: null
	});
}

function rpcReturning(data: unknown, error: unknown = null) {
	const rpc = vi.fn().mockResolvedValue({ data, error });
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function event(
	params: Record<string, string>,
	options: { method?: string; body?: unknown; url?: string } = {}
): never {
	const url = options.url ?? 'http://localhost/api/jafar/deals';
	return {
		url: new URL(url),
		params,
		cookies: {},
		request: new Request(url, {
			method: options.method ?? 'POST',
			headers: { 'content-type': 'application/json' },
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		})
	} as never;
}

beforeEach(() => vi.clearAllMocks());

describe('Deals board column', () => {
	it('refuses a caller who is not signed in', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await GET_COLUMN(
			event({}, { url: 'http://localhost/api/jafar/deals?stage=interested' })
		);
		expect(response.status).toBe(401);
	});

	it('reads the Won list like the Lost one (B5)', async () => {
		signedIn();
		const rpc = rpcReturning({ deals: [], next_cursor: null });
		const response = await GET_COLUMN(
			event({}, { url: 'http://localhost/api/jafar/deals?stage=won' })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_deal_board',
			expect.objectContaining({ target_stage: 'won' })
		);
	});

	it('refuses an unknown stage and a forged cursor', async () => {
		signedIn();
		rpcReturning({ deals: [], next_cursor: null });
		expect(
			(await GET_COLUMN(event({}, { url: 'http://localhost/api/jafar/deals?stage=sold' }))).status
		).toBe(422);
		expect(
			(
				await GET_COLUMN(
					event({}, { url: 'http://localhost/api/jafar/deals?stage=lost&cursor=not-json' })
				)
			).status
		).toBe(422);
	});

	it('hides the next page’s position behind an opaque cursor and accepts it back', async () => {
		signedIn();
		const position = { due_on: '2026-10-09', lost_at: null, id: DEAL_ID };
		rpcReturning({ deals: [], next_cursor: position });
		const first = await (
			await GET_COLUMN(event({}, { url: 'http://localhost/api/jafar/deals?stage=interested' }))
		).json();
		expect(typeof first.next_cursor).toBe('string');
		expect(first.next_cursor).not.toContain(DEAL_ID);

		const rpc = rpcReturning({ deals: [], next_cursor: null });
		await GET_COLUMN(
			event(
				{},
				{ url: `http://localhost/api/jafar/deals?stage=interested&cursor=${first.next_cursor}` }
			)
		);
		expect(rpc).toHaveBeenCalledWith('owner_deal_board', {
			target_stage: 'interested',
			cursor_due_on: '2026-10-09',
			cursor_lost_at: undefined,
			cursor_id: DEAL_ID
		});
	});
});

describe('Starting a Deal', () => {
	it('starts only at Interested or Call booked, always with a next step', async () => {
		signedIn();
		const rpc = rpcReturning(DEAL_ID);
		const late = await START(
			event(
				{},
				{ body: { relationship_id: BUSINESS_ID, stage: 'pricing_shared', next_action: STEP } }
			)
		);
		expect(late.status).toBe(422);
		const noStep = await START(
			event({}, { body: { relationship_id: BUSINESS_ID, stage: 'interested' } })
		);
		expect(noStep.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes who started it and the step to the database', async () => {
		signedIn();
		const rpc = rpcReturning(DEAL_ID);
		const response = await START(
			event({}, { body: { relationship_id: BUSINESS_ID, stage: 'call_booked', next_action: STEP } })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_deal_start', {
			actor_email: 'owner@example.com',
			target_relationship_id: BUSINESS_ID,
			target_stage: 'call_booked',
			target_next_action: STEP.text,
			target_due_on: STEP.due_on
		});
	});

	it('shows the database’s own refusal, and treats a second open Deal as a conflict', async () => {
		signedIn();
		const body = { relationship_id: BUSINESS_ID, stage: 'interested', next_action: STEP };
		rpcReturning(null, {
			code: '22023',
			message: 'This business asked not to be contacted, so it cannot have a Deal.'
		});
		const refused = await START(event({}, { body }));
		expect(refused.status).toBe(409);
		expect((await refused.json()).field_errors.form).toMatch(/asked not to be contacted/);

		rpcReturning(null, { code: '23505', message: 'duplicate key' });
		const twice = await START(event({}, { body }));
		expect(twice.status).toBe(409);
		expect((await twice.json()).field_errors.form).toBe('This business already has an open Deal.');

		rpcReturning(null);
		expect((await START(event({}, { body }))).status).toBe(404);
	});
});

describe('Moving a Deal', () => {
	it('keeps the step unless a new one is given', async () => {
		signedIn();
		const rpc = rpcReturning(true);
		await MOVE(event({ id: DEAL_ID }, { method: 'PATCH', body: { stage: 'needs_understood' } }));
		expect(rpc).toHaveBeenCalledWith(
			'owner_deal_move',
			expect.objectContaining({ target_stage: 'needs_understood', next_action_mode: 'keep' })
		);
		await MOVE(
			event({ id: DEAL_ID }, { method: 'PATCH', body: { stage: 'later', next_action: STEP } })
		);
		expect(rpc).toHaveBeenLastCalledWith(
			'owner_deal_move',
			expect.objectContaining({
				target_stage: 'later',
				next_action_mode: 'set',
				target_due_on: STEP.due_on
			})
		);
	});

	it('sends Pricing shared and Lost through their own steps', async () => {
		signedIn();
		const rpc = rpcReturning(true);
		for (const stage of ['pricing_shared', 'lost']) {
			const response = await MOVE(event({ id: DEAL_ID }, { method: 'PATCH', body: { stage } }));
			expect(response.status, stage).toBe(422);
		}
		expect(rpc).not.toHaveBeenCalled();
	});

	it('needs a reason from the list to mark a Deal Lost', async () => {
		signedIn();
		const rpc = rpcReturning(true);
		expect(
			(await LOSE(event({ id: DEAL_ID }, { body: { reason: 'asked_not_to_contact' } }))).status
		).toBe(422);
		expect(
			(await LOSE(event({ id: DEAL_ID }, { body: { reason: 'price', note: '  ' } }))).status
		).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_deal_mark_lost',
			expect.objectContaining({ reason: 'price', note: undefined })
		);
	});
});

describe('Sharing pricing', () => {
	const pro = {
		edition_id: '11111111-2222-4333-8444-555555555555',
		slug: 'pro',
		name: 'Pro',
		monthly_price_usd_cents: 12_900,
		yearly_price_usd_cents: 129_000,
		offers: {
			month: { name: 'Launch offer', intro_price_usd_cents: 4_900, periods: 2 },
			year: null
		}
	};

	it('copies the price and offers from the pricing page now, never from the browser', async () => {
		signedIn();
		mockedPackages.mockResolvedValue([pro] as never);
		const rpc = rpcReturning(true);
		const response = await SHARE(
			event(
				{ id: DEAL_ID },
				{
					body: {
						package_slugs: ['pro'],
						billing: 'year',
						follow_up: STEP,
						monthly_price_usd_cents: 1
					}
				}
			)
		);
		expect(response.status).toBe(200);
		const shared = rpc.mock.calls[0][1].shared_packages;
		expect(shared).toEqual([
			{
				edition_id: pro.edition_id,
				slug: 'pro',
				name: 'Pro',
				monthly_price_usd_cents: 12_900,
				yearly_price_usd_cents: 129_000,
				offers: pro.offers,
				link: 'http://localhost/packages/pro?billing=year'
			}
		]);
	});

	it('asks to choose again when a package left the pricing page', async () => {
		signedIn();
		mockedPackages.mockResolvedValue([pro] as never);
		const rpc = rpcReturning(true);
		const response = await SHARE(
			event({ id: DEAL_ID }, { body: { package_slugs: ['pro', 'retired'], follow_up: STEP } })
		);
		expect(response.status).toBe(409);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses the same package twice and more than five', async () => {
		signedIn();
		mockedPackages.mockResolvedValue([pro] as never);
		rpcReturning(true);
		const twice = await SHARE(
			event({ id: DEAL_ID }, { body: { package_slugs: ['pro', 'pro'], follow_up: STEP } })
		);
		expect(twice.status).toBe(422);
		const many = await SHARE(
			event(
				{ id: DEAL_ID },
				{ body: { package_slugs: ['a', 'b', 'c', 'd', 'e', 'f'], follow_up: STEP } }
			)
		);
		expect(many.status).toBe(422);
	});
});

describe('Special terms', () => {
	it('clears the terms when the box is emptied', async () => {
		signedIn();
		const rpc = rpcReturning(true);
		await SET_TERMS(event({ id: DEAL_ID }, { method: 'PATCH', body: { terms: '   ' } }));
		expect(rpc).toHaveBeenCalledWith('owner_deal_set_terms', {
			actor_email: 'owner@example.com',
			target_deal_id: DEAL_ID,
			terms: ''
		});
	});
});
