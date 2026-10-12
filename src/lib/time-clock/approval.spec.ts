import { describe, expect, it } from 'vitest';
import { approvalMessage, defaultCutoff, type ApprovalResult } from './approval';

const result = (overrides: Partial<ApprovalResult>): ApprovalResult => ({
	cutoff: '2026-10-10',
	approved_count: 12,
	approved_minutes: 900,
	people_count: 3,
	running: [],
	...overrides
});

const timer = {
	user_id: 'u',
	name: 'Sam',
	kind: 'general' as const,
	job_number: null,
	started_at: '2026-10-10T12:00:00Z',
	started_on: '2026-10-10',
	over_a_day: false
};

describe('defaultCutoff', () => {
	it('ends with the window being looked at', () => {
		expect(defaultCutoff('2026-10-10', '2026-10-12')).toBe('2026-10-10');
	});

	it('never reaches past today', () => {
		expect(defaultCutoff('2026-10-17', '2026-10-12')).toBe('2026-10-12');
	});
});

describe('approvalMessage', () => {
	it('counts entries and people', () => {
		expect(approvalMessage(result({}))).toBe('Approved 12 entries for 3 people.');
		expect(approvalMessage(result({ approved_count: 1, people_count: 1 }))).toBe(
			'Approved 1 entry for 1 person.'
		);
	});

	it('says which timers were left running', () => {
		expect(approvalMessage(result({ running: [timer] }))).toBe(
			'Approved 12 entries for 3 people. 1 running timer was not approved.'
		);
	});

	it('says when nothing was waiting', () => {
		expect(approvalMessage(result({ approved_count: 0, people_count: 0 }))).toBe(
			'Nothing was waiting for approval.'
		);
	});
});
