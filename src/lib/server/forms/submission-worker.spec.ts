import { describe, expect, it, vi } from 'vitest';
import {
	drainFormSubmissionQueue,
	processNextFormSubmission,
	type FormSubmissionWorkerClient,
	type ProcessedFormSubmissionResult
} from './submission-worker';

// A fake queue: each rpc call to process_next_form_submission pops the head, exactly like the real RPC claims
// the oldest pending row. Enough to exercise the drain loop without a database.
function fakeClient(results: ProcessedFormSubmissionResult[]) {
	const queue = [...results];
	const rpc = vi.fn(async (name: string) => {
		if (name === 'process_next_form_submission') {
			const next = queue.shift();
			return { data: next ?? { status: 'idle' }, error: null };
		}
		return { data: null, error: { message: `Unexpected RPC: ${name}` } };
	});
	return { client: { rpc } as FormSubmissionWorkerClient, rpc };
}

describe('processNextFormSubmission', () => {
	it('returns idle when the queue is empty', async () => {
		const { client } = fakeClient([]);
		await expect(processNextFormSubmission({ client })).resolves.toEqual({ status: 'idle' });
	});

	it('passes through whatever the RPC reports for a processed row', async () => {
		const { client } = fakeClient([
			{ status: 'processed', submission_id: 'sub-1', outcome: 'request' }
		]);
		await expect(processNextFormSubmission({ client })).resolves.toEqual({
			status: 'processed',
			submission_id: 'sub-1',
			outcome: 'request'
		});
	});

	it('rethrows when the RPC call itself fails', async () => {
		const rpc = vi.fn(async () => ({ data: null, error: { message: 'connection reset' } }));
		await expect(
			processNextFormSubmission({ client: { rpc } as FormSubmissionWorkerClient })
		).rejects.toThrow('connection reset');
	});
});

describe('drainFormSubmissionQueue', () => {
	it('drains every pending submission then stops idle', async () => {
		const { client } = fakeClient([
			{ status: 'processed', submission_id: 'a' },
			{ status: 'processed', submission_id: 'b' },
			{ status: 'failed', submission_id: 'c' }
		]);

		const result = await drainFormSubmissionQueue({ client });
		expect(result).toEqual({ claimed: 3, processed: 2, failed: 1, stoppedBy: 'idle' });
	});

	it('stops at the claim cap without draining the whole queue', async () => {
		const rows = Array.from({ length: 5 }, (_, i) => ({
			status: 'processed' as const,
			submission_id: `s-${i}`
		}));
		const { client } = fakeClient(rows);

		const result = await drainFormSubmissionQueue({ client, maxClaims: 2 });
		expect(result).toMatchObject({ claimed: 2, stoppedBy: 'max_claims' });
	});

	it('stops when the time budget is exhausted before the queue empties', async () => {
		const rows = Array.from({ length: 5 }, (_, i) => ({
			status: 'processed' as const,
			submission_id: `s-${i}`
		}));
		const { client } = fakeClient(rows);
		// Clock jumps past the budget after the first claim is checked.
		let ticks = 0;
		const now = () => (ticks++ === 0 ? 0 : 1000);

		const result = await drainFormSubmissionQueue({ client, timeBudgetMs: 500, now });
		expect(result).toMatchObject({ stoppedBy: 'time_budget' });
		expect(result.claimed).toBeLessThan(5);
	});
});
