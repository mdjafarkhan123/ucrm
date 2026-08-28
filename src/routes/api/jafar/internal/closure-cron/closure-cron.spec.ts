import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runOrganizationClosureCron } from '$lib/server/jafar/organization-closure-cron';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/organization-closure-cron', () => ({
	runOrganizationClosureCron: vi.fn()
}));

const mockedServerEnv = vi.mocked(getServerEnv);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRunSweep = vi.mocked(runOrganizationClosureCron);

const SECRET = 'a-long-random-cron-secret';

function requestWith(authorization?: string) {
	return {
		request: new Request('http://localhost/api/jafar/internal/closure-cron', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('closure-cron internal route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedServerEnv.mockReturnValue({ CLOSURE_CRON_SECRET: SECRET } as never);
		mockedClient.mockReturnValue({} as never);
	});

	it('rejects a request with no Authorization header', async () => {
		const response = await POST(requestWith());
		expect(response.status).toBe(401);
		expect(mockedRunSweep).not.toHaveBeenCalled();
	});

	it('rejects a request with the wrong bearer secret', async () => {
		const response = await POST(requestWith('Bearer not-the-right-secret'));
		expect(response.status).toBe(401);
		expect(mockedRunSweep).not.toHaveBeenCalled();
	});

	it('rejects a non-Bearer scheme even with the right token', async () => {
		const response = await POST(requestWith(`Basic ${SECRET}`));
		expect(response.status).toBe(401);
	});

	it('runs the sweep and returns its summary when the secret matches', async () => {
		mockedRunSweep.mockResolvedValue({
			noticesSent: 2,
			noticesSkipped: 1,
			purgesCompleted: 1,
			purgesFailed: 0,
			authCleanupsCompleted: 0,
			authCleanupsFailed: 0,
			providerCleanupsCompleted: 0,
			providerCleanupsFailed: 0
		});

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			noticesSent: 2,
			noticesSkipped: 1,
			purgesCompleted: 1,
			purgesFailed: 0,
			authCleanupsCompleted: 0,
			authCleanupsFailed: 0,
			providerCleanupsCompleted: 0,
			providerCleanupsFailed: 0
		});
	});

	it('returns 500 without leaking the error when the sweep throws', async () => {
		mockedRunSweep.mockRejectedValue(new Error('database unreachable'));

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The closure cron sweep failed.' });
	});
});
