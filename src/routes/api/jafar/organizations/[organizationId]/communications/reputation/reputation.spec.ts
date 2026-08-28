import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { POST as RESUME } from './resume/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const url = `http://localhost/api/jafar/organizations/${organizationId}/communications/reputation`;

function event(body?: unknown, params: Record<string, string> = { organizationId }) {
	return {
		params,
		request: new Request(url, {
			method: body === undefined ? 'GET' : 'POST',
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function clientWithRpc(results: Array<{ data: unknown; error: unknown }>) {
	const calls: Array<{ name: string; args: unknown }> = [];
	return {
		calls,
		rpc: vi.fn(async (name: string, args: unknown) => {
			calls.push({ name, args });
			return results.shift() ?? { data: null, error: null };
		})
	};
}

const validOverride = {
	signal: 'complaint',
	window_key: 'rolling_24h',
	pause_rate: 0.06,
	reason: 'stricter while under review'
};

describe('organization email reputation boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
	});

	it('refuses a caller without an owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects an organization identifier that is not a uuid', async () => {
		const response = await GET(event(undefined, { organizationId: 'not-a-uuid' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('records the override as the signed-in owner and returns the refreshed reputation', async () => {
		const client = clientWithRpc([
			{ data: { threshold_id: 'abc' }, error: null },
			{ data: { metrics: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event(validOverride));

		expect(response.status).toBe(200);
		expect(client.calls[0]).toMatchObject({
			name: 'set_communication_email_reputation_threshold',
			args: {
				p_scope: 'organization',
				p_organization_id: organizationId,
				p_pause_rate: 0.06,
				p_actor_email: 'owner@example.com'
			}
		});
		expect(client.calls[1]).toMatchObject({ name: 'get_communication_email_reputation' });
	});

	it('passes an override that would weaken the ceiling through as a conflict', async () => {
		const client = clientWithRpc([
			{
				data: null,
				error: {
					code: '23514',
					message: 'An organization override cannot weaken the platform ceiling.'
				}
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ ...validOverride, pause_rate: 5 }));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({
			error: 'An organization override cannot weaken the platform ceiling.'
		});
	});

	it('resumes an automatic pause with the remediation confirmation the owner gave', async () => {
		const client = clientWithRpc([
			{ data: { released: true, expired_optional_messages: 4 }, error: null },
			{ data: { metrics: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await RESUME(
			event({ reason: 'remediation complete', confirm_remediation: true }) as unknown as Parameters<
				typeof RESUME
			>[0]
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			result: { released: true, expired_optional_messages: 4 }
		});
		expect(client.calls[0]).toMatchObject({
			name: 'resume_communication_email_reputation_pause',
			args: {
				p_organization_id: organizationId,
				p_actor_email: 'owner@example.com',
				p_confirm_remediation: true
			}
		});
	});

	it('refuses a resume that is still breaching without confirmation', async () => {
		const client = clientWithRpc([
			{
				data: null,
				error: { code: '23514', message: 'This organization is still above a pause threshold.' }
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await RESUME(
			event({ reason: 'looks fine now' }) as unknown as Parameters<typeof RESUME>[0]
		);

		expect(response.status).toBe(409);
	});
});
