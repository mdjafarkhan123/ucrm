import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	acceptTeamInvitation,
	inspectTeamInvitation,
	TeamInvitationError
} from '$lib/server/team/invitations';

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
	return { ...actual, acceptTeamInvitation: vi.fn(), inspectTeamInvitation: vi.fn() };
});

const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO12';
const client = {} as never;

function getEvent(searchToken: string | null) {
	const url = new URL('https://app.example.com/api/team/invitations/accept');
	if (searchToken !== null) url.searchParams.set('token', searchToken);
	return { url, getClientAddress: () => '203.0.113.8' } as Parameters<typeof GET>[0];
}

function postEvent(body: unknown, raw = false) {
	return {
		request: new Request('https://app.example.com/api/team/invitations/accept', {
			method: 'POST',
			body: raw ? String(body) : JSON.stringify(body)
		}),
		getClientAddress: () => '203.0.113.8'
	} as Parameters<typeof POST>[0];
}

const validBody = {
	token,
	email: ' MEMBER@example.com ',
	password: 'longenough1',
	password_confirmation: 'longenough1'
};

describe('public team invitation acceptance API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(inspectTeamInvitation).mockResolvedValue({
			valid: true,
			emailHint: 'm*****@example.com',
			companyName: 'Ridgeway Electric'
		});
		vi.mocked(acceptTeamInvitation).mockResolvedValue({ accepted: true });
	});

	it('returns an invalid no-store result before privileged work for a malformed token', async () => {
		const response = await GET(getEvent('short'));
		expect(await response.json()).toEqual({ valid: false });
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('returns only the masked hint and company name for a usable token', async () => {
		const response = await GET(getEvent(token));
		expect(await response.json()).toEqual({
			valid: true,
			email_hint: 'm*****@example.com',
			company_name: 'Ridgeway Electric'
		});
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(checkRateLimit).toHaveBeenCalledWith(client, {
			bucketKey: 'team_invitation_accept_get:203.0.113.8',
			windowSeconds: 300,
			maxAttempts: 30
		});
	});

	it('keeps GET failures opaque and uncached', async () => {
		vi.mocked(inspectTeamInvitation).mockRejectedValueOnce(new Error('provider detail'));
		const response = await GET(getEvent(token));
		expect(await response.json()).toEqual({ valid: false });
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('validates POST before rate limiting or Auth work', async () => {
		const response = await POST(postEvent({ ...validBody, password_confirmation: 'different' }));
		expect(response.status).toBe(422);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(checkRateLimit).not.toHaveBeenCalled();
		expect(acceptTeamInvitation).not.toHaveBeenCalled();
	});

	it('normalizes the email and accepts with no-store', async () => {
		const response = await POST(postEvent(validBody));
		expect(acceptTeamInvitation).toHaveBeenCalledWith(client, {
			token,
			email: 'member@example.com',
			password: 'longenough1'
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ accepted: true });
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('rate limits POST per IP before acceptance', async () => {
		vi.mocked(checkRateLimit).mockResolvedValueOnce({ allowed: false, retryAfterSeconds: 90 });
		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(429);
		expect(response.headers.get('retry-after')).toBe('90');
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(acceptTeamInvitation).not.toHaveBeenCalled();
	});

	it('returns a stable public invitation error', async () => {
		vi.mocked(acceptTeamInvitation).mockRejectedValueOnce(
			new TeamInvitationError('invalid_or_expired', 'This invitation is invalid or has expired.')
		);
		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(404);
		expect(await response.json()).toEqual({
			error: 'This invitation is invalid or has expired.',
			code: 'invalid_or_expired'
		});
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
