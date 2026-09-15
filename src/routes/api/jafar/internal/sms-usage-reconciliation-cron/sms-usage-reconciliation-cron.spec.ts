import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseSmsUsageReconciliationStore } from '$lib/server/communications/sms-usage-reconciliation-store';
import { runSmsUsageReconciliationCron } from '$lib/server/communications/sms-usage-reconciliation-cron';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/sms-usage-reconciliation-store', () => ({
	createSupabaseSmsUsageReconciliationStore: vi.fn()
}));
vi.mock('$lib/server/communications/sms-usage-reconciliation-cron', () => ({
	runSmsUsageReconciliationCron: vi.fn()
}));

const mockedServerEnv = vi.mocked(getServerEnv);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRunSweep = vi.mocked(runSmsUsageReconciliationCron);

const SECRET = 'a-long-random-sms-usage-reconciliation-cron-secret';

function requestWith(authorization?: string) {
	return {
		request: new Request('http://localhost/api/jafar/internal/sms-usage-reconciliation-cron', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('sms-usage-reconciliation-cron internal route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedServerEnv.mockReturnValue({ SMS_USAGE_RECONCILIATION_CRON_SECRET: SECRET } as never);
		mockedClient.mockReturnValue({} as never);
		vi.mocked(createSupabaseSmsUsageReconciliationStore).mockReturnValue({} as never);
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
		mockedServerEnv.mockReturnValue({ SMS_USAGE_RECONCILIATION_CRON_SECRET: undefined } as never);
		const response = await POST(requestWith(`Bearer ${SECRET}`));
		expect(response.status).toBe(401);
	});

	it('rejects a non-Bearer scheme even with the right token', async () => {
		const response = await POST(requestWith(`Basic ${SECRET}`));
		expect(response.status).toBe(401);
	});

	it('runs the sweep and returns its summary when the secret matches', async () => {
		mockedRunSweep.mockResolvedValue({
			organizationsChecked: 2,
			daysChecked: 4,
			matched: 3,
			drifted: 1,
			failed: 0
		});

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			organizationsChecked: 2,
			daysChecked: 4,
			matched: 3,
			drifted: 1,
			failed: 0
		});
	});

	it('returns 500 without leaking the error when the sweep throws', async () => {
		mockedRunSweep.mockRejectedValue(new Error('database unreachable'));

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The SMS usage-reconciliation cron failed.' });
	});
});
