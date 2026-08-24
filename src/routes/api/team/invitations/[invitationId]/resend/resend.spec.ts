import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { resendTeamInvitation } from '$lib/server/team/invitations';

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
	return { ...actual, resendTeamInvitation: vi.fn() };
});

const invitationId = '00000000-0000-4000-8000-000000000013';
const organizationId = '00000000-0000-4000-8000-000000000011';
const managerId = '00000000-0000-4000-8000-000000000012';
const client = {} as never;

function event(id = invitationId) {
	return {
		request: new Request(`https://app.example.com/api/team/invitations/${id}/resend`, {
			method: 'POST'
		}),
		url: new URL(`https://app.example.com/api/team/invitations/${id}/resend`),
		params: { invitationId: id },
		locals: {}
	} as Parameters<typeof POST>[0];
}

describe('team invitation resend API', () => {
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
		vi.mocked(resendTeamInvitation).mockResolvedValue({ invitationId, status: 'sent' });
	});

	it('authorizes, rate limits, and returns a no-store success', async () => {
		const response = await POST(event());

		expect(checkRateLimit).toHaveBeenCalledWith(client, {
			bucketKey: `team_invitation_resend:${organizationId}:${managerId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		expect(resendTeamInvitation).toHaveBeenCalledWith(client, {
			organizationId,
			invitationId,
			businessName: 'Ridgeway',
			origin: 'https://app.example.com'
		});
		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('rejects an invalid id before privileged work', async () => {
		const response = await POST(event('not-an-id'));

		expect(response.status).toBe(400);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rate limits before rotating a token', async () => {
		vi.mocked(checkRateLimit).mockResolvedValueOnce({ allowed: false, retryAfterSeconds: 30 });

		const response = await POST(event());

		expect(response.status).toBe(429);
		expect(response.headers.get('retry-after')).toBe('30');
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(resendTeamInvitation).not.toHaveBeenCalled();
	});
});
