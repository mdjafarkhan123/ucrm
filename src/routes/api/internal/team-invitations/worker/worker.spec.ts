import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import { runTeamInvitationWorker } from '$lib/server/team/invitation-worker';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/team/invitation-worker', () => ({ runTeamInvitationWorker: vi.fn() }));

const secret = 'a-separate-worker-secret-at-least-32-characters';
const client = {} as never;

function eventWith(authorization?: string) {
	return {
		request: new Request('https://app.example.com/api/internal/team-invitations/worker', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('protected team invitation worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({ TEAM_INVITATION_WORKER_SECRET: secret } as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client);
		vi.mocked(runTeamInvitationWorker).mockResolvedValue({
			expired: 2,
			reservationsSwept: 1,
			claimed: 3,
			finalized: 1,
			cleaned: 1,
			retryRequired: 1
		});
	});

	it('rejects a missing worker secret before privileged work', async () => {
		const response = await POST(eventWith());

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(runTeamInvitationWorker).not.toHaveBeenCalled();
	});

	it('fails closed when the worker secret has not been configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({ TEAM_INVITATION_WORKER_SECRET: undefined } as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(401);
		expect(runTeamInvitationWorker).not.toHaveBeenCalled();
	});

	it('rejects the wrong secret and non-Bearer schemes', async () => {
		const wrong = await POST(eventWith('Bearer wrong-secret'));
		const basic = await POST(eventWith(`Basic ${secret}`));

		expect(wrong.status).toBe(401);
		expect(basic.status).toBe(401);
		expect(runTeamInvitationWorker).not.toHaveBeenCalled();
	});

	it('runs one bounded worker pass for the exact bearer secret', async () => {
		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(runTeamInvitationWorker).toHaveBeenCalledWith(client);
		expect(await response.json()).toEqual({
			expired: 2,
			reservationsSwept: 1,
			claimed: 3,
			finalized: 1,
			cleaned: 1,
			retryRequired: 1
		});
	});

	it('returns a stable no-store error without leaking worker details', async () => {
		vi.mocked(runTeamInvitationWorker).mockRejectedValueOnce(new Error('private database detail'));

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(500);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({ error: 'The invitation maintenance worker failed.' });
	});
});
