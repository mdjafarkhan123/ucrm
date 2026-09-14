import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const senderId = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown, ids: { org?: string; sender?: string } = {}) {
	const org = ids.org ?? organizationId;
	const sender = ids.sender ?? senderId;
	return {
		params: { organizationId: org, senderId: sender },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/sender-identities/${sender}/capabilities`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function senderClient(
	existing: { organization_id: string } | null = { organization_id: organizationId },
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { id: senderId, capable_sms: true },
		error: null
	}
) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'communication_sms_sender_identities') {
				const result = {
					data: existing
						? {
								id: senderId,
								capable_sms: false,
								capable_mms: false,
								capable_voice: false,
								registration_id: null,
								...existing
							}
						: null,
					error: null
				};
				const builder = {
					select: () => builder,
					eq: () => builder,
					maybeSingle: () => Promise.resolve(result)
				};
				return builder;
			}
			if (table === 'access_audit_events') return { insert: auditInsert };
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult),
		auditInsert
	};
}

describe('platform owner SMS sender capabilities boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(
			postEvent({ country_code: 'us', sender_type: 'long_code', capable_sms: true })
		);

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the sender belongs to another organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = senderClient({ organization_id: 'other-org' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ country_code: 'us', sender_type: 'long_code', capable_sms: true })
		);

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('sets the capabilities and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = senderClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ country_code: 'us', sender_type: 'long_code', capable_sms: true })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_set_sender_capabilities',
			expect.objectContaining({
				p_sender_identity_id: senderId,
				p_country_code: 'US',
				p_sender_type: 'long_code',
				p_capable_sms: true,
				p_capable_mms: false,
				p_capable_voice: false
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('translates a mismatched registration into a not-found error', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = senderClient(
			{ organization_id: organizationId },
			{ data: null, error: { code: '23503', message: 'foreign key violation' } }
		);
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({
				country_code: 'us',
				sender_type: 'long_code',
				capable_sms: true,
				registration_id: '323e4567-e89b-12d3-a456-426614174000'
			})
		);

		expect(response.status).toBe(404);
		expect((await response.json()).error).toContain('registration was not found');
	});
});
