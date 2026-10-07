import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
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

function postEvent(body: unknown, org = organizationId) {
	return {
		params: { organizationId: org },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/mode`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function getEvent(org = organizationId) {
	return { params: { organizationId: org }, cookies: {} } as Parameters<typeof GET>[0];
}

function modeClient(
	existing: Record<string, unknown> | null = {
		package_max_mode: 'operational',
		chosen_mode: 'operational',
		override_mode: null,
		override_reason: null
	},
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { organization_id: organizationId, chosen_mode: 'off' },
		error: null
	}
) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'communication_sms_org_modes') {
				const builder = {
					select: () => builder,
					eq: () => builder,
					maybeSingle: () => Promise.resolve({ data: existing, error: null })
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

describe('platform owner SMS mode read', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns the stored mode and the mode actually in effect', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = modeClient(
			{ package_max_mode: 'operational', chosen_mode: 'off', override_mode: null },
			{ data: 'off', error: null }
		);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.mode).toMatchObject({ chosen_mode: 'off' });
		expect(body.effective_mode).toBe('off');
		expect(client.rpc).toHaveBeenCalledWith('communication_sms_effective_mode', {
			p_organization_id: organizationId
		});
	});

	it('reports SMS as off with no stored row', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = modeClient(null, { data: 'off', error: null });
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.mode).toBeNull();
		expect(body.effective_mode).toBe('off');
	});
});

describe('platform owner SMS mode boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({ chosen_mode: 'off' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an empty request that changes nothing', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({}));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a reason when setting an override', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ override_mode: 'off' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects setting an override at the same time as clearing it', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(
			postEvent({ override_mode: 'off', override_reason: 'safety pause', clear_override: true })
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('sets the chosen mode with the platform-owner sentinel actor and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = modeClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ chosen_mode: 'off' }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_set_org_mode',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_set_by: PLATFORM_OWNER_ACTOR_ID,
				p_chosen_mode: 'off'
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('sets a reasoned override', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = modeClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ override_mode: 'off', override_reason: 'platform-wide safety pause' })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_set_org_mode',
			expect.objectContaining({
				p_override_mode: 'off',
				p_override_reason: 'platform-wide safety pause'
			})
		);
	});

	it('translates a database rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = modeClient(null, {
			data: null,
			error: {
				code: 'P0001',
				message: 'chosen SMS mode operational exceeds the package maximum off'
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ chosen_mode: 'operational' }));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('exceeds the package maximum');
	});
});
