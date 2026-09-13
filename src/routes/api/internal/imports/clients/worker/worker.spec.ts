import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { drainImportQueue } from '$lib/server/imports/import-worker';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/imports/import-worker', () => ({ drainImportQueue: vi.fn() }));

const secret = 'a-client-import-worker-secret-at-least-32-chars';

function eventWith(authorization?: string) {
	return {
		request: new Request('https://app.example.com/api/internal/imports/clients/worker', {
			method: 'POST',
			headers: authorization ? { authorization } : {}
		})
	} as Parameters<typeof POST>[0];
}

describe('client import worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({ CLIENT_IMPORT_WORKER_SECRET: secret } as never);
	});

	it('drains the queue and returns the result to an authorized wake', async () => {
		const drainResult = {
			claimed: 2,
			processed: 2,
			failed: 0,
			batchesCompleted: 1,
			errorFilesGenerated: 0,
			stoppedBy: 'idle'
		};
		vi.mocked(drainImportQueue).mockResolvedValue(drainResult as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual(drainResult);
		expect(drainImportQueue).toHaveBeenCalledTimes(1);
	});

	it('rejects a missing or wrong secret without draining', async () => {
		const unauthorized = await POST(eventWith());
		expect(unauthorized.status).toBe(401);

		const wrong = await POST(eventWith('Bearer not-the-secret'));
		expect(wrong.status).toBe(401);

		expect(drainImportQueue).not.toHaveBeenCalled();
	});

	it('rejects when no worker secret is configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({ CLIENT_IMPORT_WORKER_SECRET: undefined } as never);
		const response = await POST(eventWith(`Bearer ${secret}`));
		expect(response.status).toBe(401);
		expect(drainImportQueue).not.toHaveBeenCalled();
	});
});
