import { describe, expect, it } from 'vitest';
import { waitingLabel } from './waiting';

const now = new Date('2026-10-14T12:00:00Z');
const ago = (minutes: number) => new Date(now.getTime() - minutes * 60_000).toISOString();

describe('Requests list waiting line', () => {
	it('counts minutes, then hours, then days, rounded down', () => {
		expect(waitingLabel('needs_approval', ago(25), now)).toBe('Waiting 25 min');
		expect(waitingLabel('new', ago(59), now)).toBe('Waiting 59 min');
		expect(waitingLabel('new', ago(60), now)).toBe('Waiting 1 h');
		expect(waitingLabel('new', ago(6 * 60 + 40), now)).toBe('Waiting 6 h');
		expect(waitingLabel('needs_approval', ago(24 * 60), now)).toBe('Waiting 1 day');
		expect(waitingLabel('new', ago(24 * 60 * 9 + 5), now)).toBe('Waiting 9 days');
	});

	it('never says zero minutes, even for a request made a moment ago or a clock a little ahead', () => {
		expect(waitingLabel('new', ago(0), now)).toBe('Waiting 1 min');
		expect(waitingLabel('new', ago(-3), now)).toBe('Waiting 1 min');
	});

	it('only shows on requests still waiting for a first reply', () => {
		for (const status of ['unscheduled', 'today', 'upcoming', 'overdue', 'assessment_completed', 'converted']) {
			expect(waitingLabel(status, ago(30), now)).toBeNull();
		}
	});
});
