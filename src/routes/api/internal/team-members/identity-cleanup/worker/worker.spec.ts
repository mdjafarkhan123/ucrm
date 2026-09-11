import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import { runMemberIdentityWorker } from '$lib/server/team/member-identity-worker';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/team/member-identity-worker', () => ({ runMemberIdentityWorker: vi.fn() }));

const secret = 'a-separate-worker-secret-at-least-32-characters';
const client = {} as never;

function eventWith(authorization?: string) {
	return {
		request: new Request(
			'https://app.example.com/api/internal/team-members/identity-cleanup/worker',
			{
				method: 'POST',
				headers: authorization ? { authorization } : undefined
			}
		)
	} as Parameters<typeof POST>[0];
}

describe('protected member identity cleanup worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({
			TEAM_MEMBER_IDENTITY_WORKER_SECRET: secret
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client);
		vi.mocked(runMemberIdentityWorker).mockResolvedValue({
			claimed: 2,
			completed: 1,
			retryRequired: 1
		});
	});

	it('rejects a missing worker secret before privileged work', async () => {
		const response = await POST(eventWith());

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(runMemberIdentityWorker).not.toHaveBeenCalled();
	});

	it('fails closed when the worker secret has not been configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({
			TEAM_MEMBER_IDENTITY_WORKER_SECRET: undefined
		} as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(401);
		expect(runMemberIdentityWorker).not.toHaveBeenCalled();
	});

	it('rejects the wrong secret and non-Bearer schemes', async () => {
		const wrong = await POST(eventWith('Bearer wrong-secret'));
		const basic = await POST(eventWith(`Basic ${secret}`));

		expect(wrong.status).toBe(401);
		expect(basic.status).toBe(401);
		expect(runMemberIdentityWorker).not.toHaveBeenCalled();
	});

	it('runs one bounded worker pass for the exact bearer secret', async () => {
		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(runMemberIdentityWorker).toHaveBeenCalledWith(client);
		expect(await response.json()).toEqual({ claimed: 2, completed: 1, retryRequired: 1 });
	});

	it('returns a stable no-store error without leaking worker details', async () => {
		vi.mocked(runMemberIdentityWorker).mockRejectedValueOnce(new Error('private database detail'));

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(500);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({ error: 'The member identity cleanup worker failed.' });
	});
});
