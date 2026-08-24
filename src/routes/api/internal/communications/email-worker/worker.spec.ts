import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));

const secret = 'a-communications-worker-secret-at-least-32-characters';

function eventWith(authorization?: string) {
	return {
		request: new Request('https://app.example.com/api/internal/communications/email-worker', {
			method: 'POST',
			headers: authorization ? { authorization } : undefined
		})
	} as Parameters<typeof POST>[0];
}

describe('communications email worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: secret } as never);
	});

	it('fails closed before sender identity support exists', async () => {
		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(503);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({
			ready: false,
			reason: 'sender_identity_not_available'
		});
	});

	it('rejects a missing, malformed, or incorrect worker credential', async () => {
		const missing = await POST(eventWith());
		const basic = await POST(eventWith(`Basic ${secret}`));
		const wrong = await POST(eventWith('Bearer another-secret'));

		for (const response of [missing, basic, wrong]) {
			expect(response.status).toBe(401);
			expect(response.headers.get('cache-control')).toBe('no-store');
		}
	});

	it('fails closed when no worker credential is configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: undefined } as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(401);
	});
});
