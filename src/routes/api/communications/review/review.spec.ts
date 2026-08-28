import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);
const clientId = '00000000-0000-4000-8000-000000000001';

function event(body: unknown) {
	return {
		request: new Request('http://localhost/api/communications/review', {
			method: 'POST',
			body: JSON.stringify(body)
		})
	} as Parameters<typeof POST>[0];
}

describe('resolving a guarded conversation', () => {
	const rpc = vi.fn();

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'conversations.manage_assignment': true }, features: {} }
		} as never);
		mockedOwnerClient.mockReturnValue({ rpc } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		rpc.mockResolvedValue({ data: 2, error: null });
	});

	it('requires conversations.manage_assignment', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await POST(
			event({ sender_email: 'a@b.test', resolution: 'dismiss', client_id: null })
		);
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects an unknown resolution before reaching the database', async () => {
		const response = await POST(
			event({ sender_email: 'a@b.test', resolution: 'quarantine', client_id: null })
		);
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects linking without a client', async () => {
		const response = await POST(
			event({ sender_email: 'a@b.test', resolution: 'link', client_id: null })
		);
		expect(response.status).toBe(422);
		expect(await response.json()).toMatchObject({
			field_errors: { client_id: 'Choose a client to link this conversation to.' }
		});
		expect(rpc).not.toHaveBeenCalled();
	});

	it('links every pending message from the sender to the chosen client', async () => {
		const response = await POST(
			event({ sender_email: 'Stranger@Outside.test', resolution: 'link', client_id: clientId })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('resolve_inbound_message_review', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_sender_email: 'Stranger@Outside.test',
			target_resolution: 'link',
			target_client_id: clientId
		});
		expect(await response.json()).toEqual({
			resolution: 'link',
			resolved_count: 2,
			client_id: clientId
		});
	});

	it('never forwards a client when dismissing, even if one is supplied', async () => {
		rpc.mockResolvedValue({ data: 1, error: null });
		const response = await POST(
			event({ sender_email: 'junk@outside.test', resolution: 'dismiss', client_id: clientId })
		);
		expect(response.status).toBe(200);
		expect(rpc.mock.calls[0][1]).toMatchObject({ target_client_id: undefined });
	});

	it('surfaces an actionable database refusal to the operator', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '55000', message: 'This conversation no longer needs review.' }
		});
		const response = await POST(
			event({ sender_email: 'a@b.test', resolution: 'dismiss', client_id: null })
		);
		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({ error: 'This conversation no longer needs review.' });
	});

	it('hides an unexpected database failure behind a generic error', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: '42P01', message: 'relation missing' } });
		const response = await POST(
			event({ sender_email: 'a@b.test', resolution: 'dismiss', client_id: null })
		);
		expect(response.status).toBe(500);
		expect(await response.text()).not.toContain('relation missing');
	});

	it('rate-limits repeated resolution attempts', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const response = await POST(
			event({ sender_email: 'a@b.test', resolution: 'dismiss', client_id: null })
		);
		expect(response.status).toBe(429);
		expect(rpc).not.toHaveBeenCalled();
	});
});
