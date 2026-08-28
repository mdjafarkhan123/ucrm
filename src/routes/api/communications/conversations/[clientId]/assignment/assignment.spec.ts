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
const memberId = '00000000-0000-4000-8000-000000000002';

function event(body: unknown) {
	return {
		params: { clientId },
		request: new Request(
			`http://localhost/api/communications/conversations/${clientId}/assignment`,
			{
				method: 'POST',
				body: JSON.stringify(body)
			}
		)
	} as Parameters<typeof POST>[0];
}

describe('assigning a conversation', () => {
	const upsert = vi.fn();
	const del = vi.fn();
	const from = vi.fn(() => ({
		upsert,
		delete: () => ({ eq: () => ({ eq: del }) })
	}));

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'conversations.manage_assignment': true }, features: {} }
		} as never);
		mockedOwnerClient.mockReturnValue({ from } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		upsert.mockResolvedValue({ error: null });
		del.mockResolvedValue({ error: null });
	});

	it('requires conversations.manage_assignment', async () => {
		await POST(event({ assigned_to: memberId }));
		expect(mockedRequire).toHaveBeenCalledWith(
			expect.anything(),
			'conversations.manage_assignment'
		);
	});

	it('rejects a malformed assigned_to', async () => {
		const response = await POST(event({ assigned_to: 'not-a-uuid' }));
		expect(response.status).toBe(422);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('upserts the assignment, keyed on organization and client', async () => {
		const response = await POST(event({ assigned_to: memberId }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ assigned_to: memberId });
		expect(upsert).toHaveBeenCalledWith(
			expect.objectContaining({
				organization_id: 'org-1',
				client_id: clientId,
				assigned_to: memberId,
				assigned_by: 'user-1'
			}),
			{ onConflict: 'organization_id,client_id' }
		);
	});

	it('clears the assignment (Unassigned) when assigned_to is null', async () => {
		const response = await POST(event({ assigned_to: null }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ assigned_to: null });
		expect(del).toHaveBeenCalledWith('client_id', clientId);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('maps the eligibility trigger rejection to a friendly field error', async () => {
		upsert.mockResolvedValue({
			error: { code: '23514', message: 'That person cannot be assigned conversations.' }
		});
		const response = await POST(event({ assigned_to: memberId }));
		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({
			error: 'Please review the highlighted fields.',
			field_errors: { assigned_to: 'That person cannot be assigned conversations.' }
		});
	});

	it('maps a foreign key rejection (unknown conversation) to a validation error', async () => {
		upsert.mockResolvedValue({ error: { code: '23503' } });
		const response = await POST(event({ assigned_to: memberId }));
		expect(response.status).toBe(422);
	});
});
