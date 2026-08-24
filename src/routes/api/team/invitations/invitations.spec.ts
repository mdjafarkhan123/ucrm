import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { createTeamInvitation, TeamInvitationError } from '$lib/server/team/invitations';

vi.mock('$lib/server/access/contractor', () => ({ requireContractorTeamAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});
vi.mock('$lib/server/team/invitations', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/team/invitations')>(
		'$lib/server/team/invitations'
	);
	return { ...actual, createTeamInvitation: vi.fn() };
});

const organizationId = '00000000-0000-4000-8000-000000000011';
const managerId = '00000000-0000-4000-8000-000000000012';
const client = {} as never;

function event(body: unknown, raw = false) {
	return {
		request: new Request('https://app.example.com/api/team/invitations', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: raw ? String(body) : JSON.stringify(body)
		}),
		url: new URL('https://app.example.com/api/team/invitations'),
		locals: {}
	} as Parameters<typeof POST>[0];
}

describe('team invitation create API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireContractorTeamAdmin).mockResolvedValue({
			context: {
				auth: {
					user: { id: managerId },
					organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
				},
				access: { features: { 'core.team': true }, permissions: { 'team.manage': true } }
			} as never
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(createTeamInvitation).mockResolvedValue({
			invitationId: 'invitation-1',
			status: 'sent'
		});
	});

	it('returns the authorization response without touching privileged services', async () => {
		vi.mocked(requireContractorTeamAdmin).mockResolvedValueOnce({
			response: new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
		});

		const response = await POST(event({}));

		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('validates before rate limiting or creating Auth state', async () => {
		const response = await POST(event({ email: 'bad', role: 'owner' }));

		expect(response.status).toBe(422);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(checkRateLimit).not.toHaveBeenCalled();
		expect(createTeamInvitation).not.toHaveBeenCalled();
	});

	it('creates a normalized invitation and returns no-store', async () => {
		const response = await POST(
			event({ email: ' MEMBER@example.COM ', role: 'field', permission_adjustments: [] })
		);

		expect(checkRateLimit).toHaveBeenCalledWith(client, {
			bucketKey: `team_invitation_create:${organizationId}:${managerId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		expect(createTeamInvitation).toHaveBeenCalledWith(client, {
			organizationId,
			invitedBy: managerId,
			email: 'member@example.com',
			role: 'field',
			permissionAdjustments: [],
			businessName: 'Ridgeway',
			origin: 'https://app.example.com'
		});
		expect(response.status).toBe(201);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('rate limits before creating the invitation', async () => {
		vi.mocked(checkRateLimit).mockResolvedValueOnce({ allowed: false, retryAfterSeconds: 42 });

		const response = await POST(event({ email: 'member@example.com', role: 'field' }));

		expect(response.status).toBe(429);
		expect(response.headers.get('retry-after')).toBe('42');
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(createTeamInvitation).not.toHaveBeenCalled();
	});

	it('keeps a delivery failure retryable and visible', async () => {
		vi.mocked(createTeamInvitation).mockResolvedValueOnce({
			invitationId: 'invitation-1',
			status: 'delivery_failed'
		});

		const response = await POST(event({ email: 'member@example.com', role: 'field' }));

		expect(response.status).toBe(202);
		expect(await response.json()).toEqual({
			invitationId: 'invitation-1',
			status: 'delivery_failed'
		});
	});

	it('returns a stable conflict without leaking provider details', async () => {
		vi.mocked(createTeamInvitation).mockRejectedValueOnce(
			new TeamInvitationError('email_in_use', 'That email cannot be invited.')
		);

		const response = await POST(event({ email: 'member@example.com', role: 'field' }));

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'That email cannot be invited.',
			code: 'email_in_use'
		});
	});
});
