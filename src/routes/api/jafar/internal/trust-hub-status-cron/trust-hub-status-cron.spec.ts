import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTrustHubSubmissionStore } from '$lib/server/communications/trust-hub-submission-store';
import { createTwilioTrustHubClient } from '$lib/server/communications/twilio-trust-hub';
import { createSupabaseTrustHubStatusTriggerStore } from '$lib/server/communications/trust-hub-status-trigger-store';
import { runTrustHubStatusPollCron } from '$lib/server/communications/trust-hub-status-poll-cron';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/trust-hub-submission-store', () => ({
	createSupabaseTrustHubSubmissionStore: vi.fn()
}));
vi.mock('$lib/server/communications/twilio-trust-hub', () => ({
	createTwilioTrustHubClient: vi.fn()
}));
vi.mock('$lib/server/communications/trust-hub-status-trigger-store', () => ({
	createSupabaseTrustHubStatusTriggerStore: vi.fn()
}));
vi.mock('$lib/server/communications/trust-hub-status-poll-cron', () => ({
	runTrustHubStatusPollCron: vi.fn()
}));

const mockedServerEnv = vi.mocked(getServerEnv);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRunSweep = vi.mocked(runTrustHubStatusPollCron);

const SECRET = 'a-long-random-trust-hub-cron-secret-value';

function requestWith(authorization?: string) {
	return {
		request: new Request('http://localhost/api/jafar/internal/trust-hub-status-cron', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('trust-hub-status-cron internal route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedServerEnv.mockReturnValue({ TRUST_HUB_STATUS_CRON_SECRET: SECRET } as never);
		mockedClient.mockReturnValue({} as never);
		vi.mocked(createSupabaseTrustHubSubmissionStore).mockReturnValue({} as never);
		vi.mocked(createTwilioTrustHubClient).mockReturnValue({} as never);
		vi.mocked(createSupabaseTrustHubStatusTriggerStore).mockReturnValue({} as never);
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

	it('rejects when the secret is not configured at all', async () => {
		mockedServerEnv.mockReturnValue({ TRUST_HUB_STATUS_CRON_SECRET: undefined } as never);
		const response = await POST(requestWith(`Bearer ${SECRET}`));
		expect(response.status).toBe(401);
	});

	it('rejects a non-Bearer scheme even with the right token', async () => {
		const response = await POST(requestWith(`Basic ${SECRET}`));
		expect(response.status).toBe(401);
	});

	it('runs the sweep and returns its summary when the secret matches', async () => {
		mockedRunSweep.mockResolvedValue({
			checked: 3,
			approved: 1,
			actionNeeded: 1,
			stillPending: 1,
			failed: 0
		});

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			checked: 3,
			approved: 1,
			actionNeeded: 1,
			stillPending: 1,
			failed: 0
		});
	});

	it('returns 500 without leaking the error when the sweep throws', async () => {
		mockedRunSweep.mockRejectedValue(new Error('database unreachable'));

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The Trust Hub status poll cron failed.' });
	});
});
