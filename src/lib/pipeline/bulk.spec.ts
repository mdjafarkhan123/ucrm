import { describe, expect, it } from 'vitest';
import { cardCount, summarizeBulk } from './bulk';

describe('summarizeBulk', () => {
	it('counts what changed and groups each refusal reason once, most common first', () => {
		const summary = summarizeBulk([
			{ id: 'a', status: 'done' },
			{ id: 'b', status: 'unchanged' },
			{ id: 'c', status: 'refused', reason: 'Five open tasks already.', code: null },
			{ id: 'd', status: 'refused', reason: 'Needs a future task.', code: 'needs_future_task' },
			{ id: 'e', status: 'refused', reason: 'Needs a future task.', code: 'needs_future_task' }
		]);

		expect(summary.done).toBe(1);
		expect(summary.unchanged).toBe(1);
		expect(summary.refusedIds).toEqual(['c', 'd', 'e']);
		expect(summary.reasons).toEqual([
			{ reason: 'Needs a future task.', count: 2 },
			{ reason: 'Five open tasks already.', count: 1 }
		]);
	});

	it('says card or cards', () => {
		expect(cardCount(1)).toBe('1 card');
		expect(cardCount(5)).toBe('5 cards');
	});
});
