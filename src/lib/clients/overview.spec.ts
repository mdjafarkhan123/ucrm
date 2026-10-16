import { describe, expect, it } from 'vitest';
import { newClientsChange, periodLabel } from './overview';

describe('New clients card wording', () => {
	it('says how many more or fewer than the 30 days before', () => {
		expect(newClientsChange(14, 10)).toEqual({
			direction: 'up',
			text: '4 more than the 30 days before'
		});
		expect(newClientsChange(3, 8)).toEqual({
			direction: 'down',
			text: '5 fewer than the 30 days before'
		});
		expect(newClientsChange(6, 6)).toEqual({
			direction: 'same',
			text: 'Same as the 30 days before'
		});
	});

	it('has nothing to compare when both windows are empty', () => {
		expect(newClientsChange(0, 0)).toBeNull();
		expect(newClientsChange(2, 0)?.text).toBe('2 more than the 30 days before');
	});

	it('names the window by its calendar days', () => {
		expect(periodLabel('2026-09-15', '2026-10-14', 'en-US')).toBe('Sep 15 – Oct 14');
		expect(periodLabel('2026-12-03', '2027-01-01', 'en-US')).toBe('Dec 3 – Jan 1');
	});
});
