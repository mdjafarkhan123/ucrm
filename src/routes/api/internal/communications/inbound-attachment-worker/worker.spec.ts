import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getServerEnv } from '$lib/server/env';
import { runCommunicationInboundAttachmentWorker } from '$lib/server/communications/inbound-attachment-worker';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/communications/inbound-attachment-worker', () => ({
	runCommunicationInboundAttachmentWorker: vi.fn()
}));

const secret = 'a-communications-worker-secret-at-least-32-characters';

function eventWith(authorization?: string) {
	return {
		request: new Request(
			'https://app.example.com/api/internal/communications/inbound-attachment-worker',
			{ method: 'POST', headers: authorization ? { authorization } : undefined }
		)
	} as Parameters<typeof POST>[0];
}

describe('communications inbound attachment worker route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: secret } as never);
	});

	it('rejects a missing, malformed, or incorrect worker credential', async () => {
		const missing = await POST(eventWith());
		const basic = await POST(eventWith(`Basic ${secret}`));
		const wrong = await POST(eventWith('Bearer another-secret'));

		for (const response of [missing, basic, wrong]) {
			expect(response.status).toBe(401);
			expect(response.headers.get('cache-control')).toBe('no-store');
		}
		expect(runCommunicationInboundAttachmentWorker).not.toHaveBeenCalled();
	});

	it('fails closed when no worker credential is configured', async () => {
		vi.mocked(getServerEnv).mockReturnValue({ COMMUNICATIONS_WORKER_SECRET: undefined } as never);

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(401);
	});

	it('stops after one empty batch and reports a summary', async () => {
		vi.mocked(runCommunicationInboundAttachmentWorker).mockResolvedValueOnce({
			claimed: 0,
			imported: 0,
			failed: 0
		});

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(response.status).toBe(200);
		expect(runCommunicationInboundAttachmentWorker).toHaveBeenCalledTimes(1);
		expect(await response.json()).toEqual({ batches: 1, claimed: 0, imported: 0, failed: 0 });
	});

	it('loops across batches until a claim comes back empty', async () => {
		vi.mocked(runCommunicationInboundAttachmentWorker)
			.mockResolvedValueOnce({ claimed: 20, imported: 19, failed: 1 })
			.mockResolvedValueOnce({ claimed: 5, imported: 5, failed: 0 })
			.mockResolvedValueOnce({ claimed: 0, imported: 0, failed: 0 });

		const response = await POST(eventWith(`Bearer ${secret}`));

		expect(runCommunicationInboundAttachmentWorker).toHaveBeenCalledTimes(3);
		expect(await response.json()).toEqual({ batches: 3, claimed: 25, imported: 24, failed: 1 });
	});
});
