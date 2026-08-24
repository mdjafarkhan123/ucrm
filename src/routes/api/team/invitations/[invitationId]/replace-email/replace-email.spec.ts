import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { replaceTeamInvitationEmail, TeamInvitationError } from '$lib/server/team/invitations';

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
	return { ...actual, replaceTeamInvitationEmail: vi.fn() };
});

const invitationId = '00000000-0000-4000-8000-000000000013';
const organizationId = '00000000-0000-4000-8000-000000000011';
const managerId = '00000000-0000-4000-8000-000000000012';
const client = {} as never;

function event(body: unknown = { email: ' New.Member@Example.COM ' }, id = invitationId) {
	return {
		request: new Request(`https://app.example.com/api/team/invitations/${id}/replace-email`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		url: new URL(`https://app.example.com/api/team/invitations/${id}/replace-email`),
		params: { invitationId: id },
		locals: {}
	} as Parameters<typeof POST>[0];
}

describe('team invitation replace-email API', () => {
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
		vi.mocked(replaceTeamInvitationEmail).mockResolvedValue({
			invitationId: 'replacement-invitation',
			status: 'sent'
		});
	});

	it('authorizes, rate limits, normalizes the email, and returns no-store', async () => {
		const response = await POST(event());

		expect(checkRateLimit).toHaveBeenCalledWith(client, {
			bucketKey: `team_invitation_replace_email:${organizationId}:${managerId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		expect(replaceTeamInvitationEmail).toHaveBeenCalledWith(client, {
			organizationId,
			invitationId,
			replacedBy: managerId,
			email: 'new.member@example.com',
			businessName: 'Ridgeway',
			origin: 'https://app.example.com'
		});
		expect(response.status).toBe(201);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('rejects invalid input before privileged work', async () => {
		const response = await POST(event({ email: 'not-an-email' }));

		expect(response.status).toBe(422);
		expect(await response.json()).toMatchObject({
			field_errors: { email: 'Enter a valid email address.' }
		});
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects a malformed invitation id before privileged work', async () => {
		const response = await POST(event(undefined, 'not-an-id'));

		expect(response.status).toBe(400);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rate limits before replacement orchestration', async () => {
		vi.mocked(checkRateLimit).mockResolvedValueOnce({ allowed: false, retryAfterSeconds: 30 });

		const response = await POST(event());

		expect(response.status).toBe(429);
		expect(response.headers.get('retry-after')).toBe('30');
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(replaceTeamInvitationEmail).not.toHaveBeenCalled();
	});

	it('returns a stable conflict while acceptance is in progress', async () => {
		vi.mocked(replaceTeamInvitationEmail).mockRejectedValueOnce(
			new TeamInvitationError(
				'acceptance_in_progress',
				'This invitation is being accepted right now. Try again shortly.'
			)
		);

		const response = await POST(event());

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'This invitation is being accepted right now. Try again shortly.',
			code: 'acceptance_in_progress'
		});
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('keeps delivery failures retryable without reporting a full failure', async () => {
		vi.mocked(replaceTeamInvitationEmail).mockResolvedValueOnce({
			invitationId: 'replacement-invitation',
			status: 'delivery_failed'
		});

		const response = await POST(event());

		expect(response.status).toBe(202);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
