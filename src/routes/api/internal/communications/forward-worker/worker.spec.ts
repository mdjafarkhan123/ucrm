import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { drainCommunicationForwardQueue } from '$lib/server/communications/forward-worker';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/communications/forward-worker', () => ({
	drainCommunicationForwardQueue: vi.fn()
}));

const secret = 'a-communications-worker-secret-at-least-32-characters';

function eventWith(authorization?: string) {
	return {
		request: new Request('https://app.example.com/api/internal/communications/forward-worker', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('communications forward worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: secret } as never);
	});

	it('runs the bounded drain and returns its result to an authorized wake', async () => {
		const drainResult = {
			staleClaimsQuarantined: 0,
			claimed: 1,
			submitted: 1,
			retried: 0,
			cancelled: 0,
			submissionUnknown: 0,
			stoppedBy: 'idle'
		};
		vi.mocked(drainCommunicationForwardQueue).mockResolvedValue(drainResult as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual(drainResult);
		expect(drainCommunicationForwardQueue).toHaveBeenCalledTimes(1);
	});

	it('rejects a missing, malformed, or incorrect worker credential without draining', async () => {
		const missing = await POST(eventWith());
		const basic = await POST(eventWith(`Basic ${secret}`));
		const wrong = await POST(eventWith('Bearer another-secret'));

		for (const response of [missing, basic, wrong]) {
			expect(response.status).toBe(401);
			expect(response.headers.get('cache-control')).toBe('no-store');
		}
		expect(drainCommunicationForwardQueue).not.toHaveBeenCalled();
	});

	it('fails closed when no worker credential is configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: undefined } as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(401);
	});
});
