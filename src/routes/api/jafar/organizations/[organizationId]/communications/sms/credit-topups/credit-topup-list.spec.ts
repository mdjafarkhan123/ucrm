import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function session() {
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		memberId: null,
		name: null
	};
}

function getEvent(org = organizationId) {
	return { params: { organizationId: org }, cookies: {} } as Parameters<typeof GET>[0];
}

function topupListClient({
	requests = [],
	account = null,
	promotionalBalance = 0,
	spendableBalance = 0
}: {
	requests?: Record<string, unknown>[];
	account?: Record<string, unknown> | null;
	promotionalBalance?: number;
	spendableBalance?: number;
} = {}) {
	return {
		from: (table: string) => {
			if (table === 'communication_sms_credit_topup_requests') {
				const builder = {
					select: () => builder,
					eq: () => builder,
					order: () => Promise.resolve({ data: requests, error: null })
				};
				return builder;
			}
			if (table === 'communication_sms_credit_accounts') {
				const builder = {
					select: () => builder,
					eq: () => builder,
					maybeSingle: () => Promise.resolve({ data: account, error: null })
				};
				return builder;
			}
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn((name: string) => {
			if (name === 'communication_sms_promotional_balance') {
				return Promise.resolve({ data: promotionalBalance, error: null });
			}
			if (name === 'communication_sms_spendable_balance') {
				return Promise.resolve({ data: spendableBalance, error: null });
			}
			throw new Error(`Unexpected rpc: ${name}`);
		})
	};
}

describe('platform owner SMS credit top-up read', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid organization identifier before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await GET(getEvent('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists this organization requests and its current balance', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = topupListClient({
			requests: [
				{ id: 'req-1', status: 'awaiting_confirmation' },
				{ id: 'req-2', status: 'confirmed' }
			],
			account: {
				currency_code: 'USD',
				settled_balance_minor: 5000,
				reserved_balance_minor: 200,
				updated_at: '2026-09-01T00:00:00Z'
			},
			promotionalBalance: 300,
			spendableBalance: 5100
		});
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.requests).toHaveLength(2);
		expect(body.requests[0]).toMatchObject({ id: 'req-1', status: 'awaiting_confirmation' });
		expect(body.balance).toEqual({
			currency_code: 'USD',
			settled_balance_minor: 5000,
			reserved_balance_minor: 200,
			promotional_balance_minor: 300,
			spendable_balance_minor: 5100
		});
	});

	it('defaults the balance when the organization has no credit account yet', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = topupListClient();
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.balance).toEqual({
			currency_code: 'USD',
			settled_balance_minor: 0,
			reserved_balance_minor: 0,
			promotional_balance_minor: 0,
			spendable_balance_minor: 0
		});
	});
});
