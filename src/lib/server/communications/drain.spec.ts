import { describe, expect, it, vi } from 'vitest';
import { runBoundedDrain, type DrainProcessResult } from './drain';

// A processOne stub that returns each queued outcome in order, then 'idle' forever.
function queued(...outcomes: DrainProcessResult['status'][]) {
	const queue = [...outcomes];
	return vi.fn(async (): Promise<DrainProcessResult> => {
		const next = queue.shift();
		return next && next !== 'idle' ? { status: next } : { status: 'idle' };
	});
}

describe('runBoundedDrain', () => {
	it('quarantines once, then drains every claimable row until the queue is idle', async () => {
		const quarantine = vi.fn(async () => 4);
		const processOne = queued('submitted', 'retry', 'submitted');

		const result = await runBoundedDrain(quarantine, processOne, { concurrency: 1 });

		expect(quarantine).toHaveBeenCalledTimes(1);
		expect(result).toEqual({
			staleClaimsQuarantined: 4,
			claimed: 3,
			submitted: 2,
			retried: 1,
			cancelled: 0,
			submissionUnknown: 0,
			stoppedBy: 'idle'
		});
	});

	it('stops at the maximum claim count without overshooting across slots', async () => {
		const processOne = vi.fn(async (): Promise<DrainProcessResult> => ({ status: 'submitted' }));

		const result = await runBoundedDrain(async () => 0, processOne, {
			concurrency: 3,
			maxClaims: 5
		});

		expect(result.claimed).toBe(5);
		expect(result.submitted).toBe(5);
		expect(result.stoppedBy).toBe('max_claims');
		expect(processOne).toHaveBeenCalledTimes(5);
	});

	it('stops when the time budget is exhausted before the queue drains', async () => {
		let clock = 1000;
		const now = () => clock;
		// Each processed claim advances the injected clock so the budget trips after two claims.
		const processOne = vi.fn(async (): Promise<DrainProcessResult> => {
			clock += 60;
			return { status: 'submitted' };
		});

		const result = await runBoundedDrain(async () => 0, processOne, {
			concurrency: 1,
			maxClaims: 100,
			timeBudgetMs: 100,
			now
		});

		expect(result.claimed).toBe(2);
		expect(result.stoppedBy).toBe('time_budget');
	});

	it('tallies each terminal outcome', async () => {
		const processOne = queued('submitted', 'cancelled', 'submission_unknown', 'retry');

		const result = await runBoundedDrain(async () => 0, processOne, { concurrency: 1 });

		expect(result).toMatchObject({
			submitted: 1,
			cancelled: 1,
			submissionUnknown: 1,
			retried: 1,
			claimed: 4
		});
	});

	it('releases the reservation and rethrows when a claim attempt fails', async () => {
		const processOne = vi.fn(async () => {
			throw new Error('database unavailable');
		});

		await expect(runBoundedDrain(async () => 0, processOne, { concurrency: 1 })).rejects.toThrow(
			'database unavailable'
		);
	});
});
