import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown) {
	return {
		params: {},
		request: new Request('http://localhost/api/jafar/communications/sms/retail-rates', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function rateClient(rpcResult: { data: unknown; error: { code: string; message: string } | null }) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'platform_audit_events') return { insert: auditInsert };
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult),
		auditInsert
	};
}

const validRate = {
	destination: 'US',
	sender_type: 'long_code',
	message_unit: 'segment',
	retail_rate_major: 0.0079
};

describe('platform owner SMS retail rate publication boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent(validRate));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid destination without calling the database', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ ...validRate, destination: 'USA' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('publishes a rate with no password reconfirmation and records a platform audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = rateClient({
			data: { id: 'rate-1', destination: 'US', retail_rate_major: 0.0079 },
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validRate));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_set_retail_rate',
			expect.objectContaining({
				p_destination: 'US',
				p_sender_type: 'long_code',
				p_message_unit: 'segment',
				p_retail_rate_major: 0.0079,
				p_set_by: PLATFORM_OWNER_ACTOR_ID,
				p_currency_code: 'USD'
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('translates a retroactive-effective-date rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = rateClient({
			data: null,
			error: {
				code: 'P0001',
				message: 'a retail rate takes effect now or in the future, never retroactively'
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validRate));

		expect(response.status).toBe(409);
	});
});
