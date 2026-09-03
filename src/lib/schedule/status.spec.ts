import { describe, expect, it } from 'vitest';
import { visitDerivedStatus, visitShape } from '$lib/schedule/status';

const TODAY = '2026-09-02';

describe('visitShape', () => {
	it('reads the backlog, anytime and booked shapes off the stored columns', () => {
		expect(visitShape({ visit_date: null, start_time: null })).toBe('unscheduled');
		expect(visitShape({ visit_date: TODAY, start_time: null })).toBe('anytime');
		expect(visitShape({ visit_date: TODAY, start_time: '09:00:00' })).toBe('scheduled');
	});
});

describe('visitDerivedStatus', () => {
	const open = { start_time: '09:00:00', completed_at: null };

	it('names the day a visit sits on relative to the contractor’s own today', () => {
		expect(visitDerivedStatus({ ...open, visit_date: '2026-09-01' }, TODAY)).toBe('late');
		expect(visitDerivedStatus({ ...open, visit_date: TODAY }, TODAY)).toBe('today');
		expect(visitDerivedStatus({ ...open, visit_date: '2026-09-03' }, TODAY)).toBe('upcoming');
	});

	it('keeps a visit booked earlier today out of Late until its day has passed', () => {
		expect(
			visitDerivedStatus({ visit_date: TODAY, start_time: '06:00:00', completed_at: null }, TODAY)
		).toBe('today');
	});

	it('lets completion beat every date', () => {
		const completed_at = '2026-09-01T15:00:00.000Z';
		expect(
			visitDerivedStatus({ visit_date: '2026-09-01', start_time: null, completed_at }, TODAY)
		).toBe('completed');
		expect(visitDerivedStatus({ visit_date: null, start_time: null, completed_at }, TODAY)).toBe(
			'completed'
		);
	});

	it('gives an open backlog visit no status at all', () => {
		expect(
			visitDerivedStatus({ visit_date: null, start_time: null, completed_at: null }, TODAY)
		).toBeNull();
	});
});
