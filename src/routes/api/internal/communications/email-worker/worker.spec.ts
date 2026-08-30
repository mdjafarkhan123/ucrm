import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { runMonitoredEmailWake } from '$lib/server/communications/email-worker';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/communications/email-worker', () => ({
	runMonitoredEmailWake: vi.fn()
}));

const secret = 'a-communications-worker-secret-at-least-32-characters';

function eventWith(authorization?: string, headers: Record<string, string> = {}) {
	return {
		request: new Request('https://app.example.com/api/internal/communications/email-worker', {
			method: 'POST',
			headers: authorization ? { authorization, ...headers } : headers
		})
	} as Parameters<typeof POST>[0];
}

describe('communications email worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: secret } as never);
	});

	it('runs one monitored wake and returns its result to an authorized wake', async () => {
		const wakeResult = {
			outcome: 'idle',
			staleClaimsQuarantined: 1,
			claimed: 2,
			submitted: 2,
			retried: 0,
			cancelled: 0,
			submissionUnknown: 0,
			stoppedBy: 'idle'
		};
		vi.mocked(runMonitoredEmailWake).mockResolvedValue(wakeResult as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual(wakeResult);
		expect(runMonitoredEmailWake).toHaveBeenCalledTimes(1);
	});

	it('passes the cron wake correlation id through to the monitored wake', async () => {
		vi.mocked(runMonitoredEmailWake).mockResolvedValue({ outcome: 'idle' } as never);

		await POST(eventWith(`Bearer ${secret}`, { 'x-wake-correlation-id': 'wake-42' }));

		expect(runMonitoredEmailWake).toHaveBeenCalledWith(
			expect.objectContaining({ wakeCorrelationId: 'wake-42' })
		);
	});

	it('generates a correlation id for a manual invocation with no wake header', async () => {
		vi.mocked(runMonitoredEmailWake).mockResolvedValue({ outcome: 'idle' } as never);

		await POST(eventWith(`Bearer ${secret}`));

		const passed = vi.mocked(runMonitoredEmailWake).mock.calls[0][0].wakeCorrelationId;
		expect(passed).toMatch(/[0-9a-f-]{36}/i);
	});

	it('rejects a missing, malformed, or incorrect worker credential without waking', async () => {
		const missing = await POST(eventWith());
		const basic = await POST(eventWith(`Basic ${secret}`));
		const wrong = await POST(eventWith('Bearer another-secret'));

		for (const response of [missing, basic, wrong]) {
			expect(response.status).toBe(401);
			expect(response.headers.get('cache-control')).toBe('no-store');
		}
		expect(runMonitoredEmailWake).not.toHaveBeenCalled();
	});

	it('fails closed when no worker credential is configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: undefined } as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(401);
	});
});
