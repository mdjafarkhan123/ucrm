import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseSmsPriceReconciliationStore } from '$lib/server/communications/sms-price-reconciliation-store';
import { runSmsPriceReconciliationCron } from '$lib/server/communications/sms-price-reconciliation-cron';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/sms-price-reconciliation-store', () => ({
	createSupabaseSmsPriceReconciliationStore: vi.fn()
}));
vi.mock('$lib/server/communications/sms-price-reconciliation-cron', () => ({
	runSmsPriceReconciliationCron: vi.fn()
}));

const mockedServerEnv = vi.mocked(getServerEnv);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRunSweep = vi.mocked(runSmsPriceReconciliationCron);

const SECRET = 'a-long-random-sms-price-reconciliation-cron-secret';

function requestWith(authorization?: string) {
	return {
		request: new Request('http://localhost/api/jafar/internal/sms-price-reconciliation-cron', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('sms-price-reconciliation-cron internal route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedServerEnv.mockReturnValue({ SMS_PRICE_RECONCILIATION_CRON_SECRET: SECRET } as never);
		mockedClient.mockReturnValue({} as never);
		vi.mocked(createSupabaseSmsPriceReconciliationStore).mockReturnValue({} as never);
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
		mockedServerEnv.mockReturnValue({ SMS_PRICE_RECONCILIATION_CRON_SECRET: undefined } as never);
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
			settled: 1,
			stillPending: 1,
			escalated: 0,
			failed: 1
		});

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			checked: 3,
			settled: 1,
			stillPending: 1,
			escalated: 0,
			failed: 1
		});
	});

	it('returns 500 without leaking the error when the sweep throws', async () => {
		mockedRunSweep.mockRejectedValue(new Error('database unreachable'));

		const response = await POST(requestWith(`Bearer ${SECRET}`));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The SMS price-reconciliation cron failed.' });
	});
});
