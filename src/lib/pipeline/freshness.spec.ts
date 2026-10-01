import { describe, expect, it } from 'vitest';
import { inactivity, stageAge } from './freshness';

const now = Date.parse('2026-10-01T12:00:00.000Z');
const daysAgo = (days: number) => new Date(now - days * 24 * 60 * 60 * 1000).toISOString();

describe('stageAge', () => {
	it('is plain context at any age', () => {
		expect(stageAge(daysAgo(21), now)).toEqual({
			label: '21d',
			description: 'In this stage for 21 days'
		});
		expect(stageAge(daysAgo(0.5), now).label).toBe('12h');
	});
});

describe('inactivity', () => {
	it('warns a New request untouched for two days', () => {
		expect(inactivity('new_request', daysAgo(2), now)).toEqual({
			days: 2,
			label: 'No progress for 2 days'
		});
	});

	it('stays quiet inside the stage limit', () => {
		expect(inactivity('new_request', daysAgo(0.9), now)).toBeNull();
		expect(inactivity('quote_awaiting_response', daysAgo(4.9), now)).toBeNull();
		expect(inactivity('quote_awaiting_response', daysAgo(5), now)?.days).toBe(5);
	});

	it('uses each stage’s own default', () => {
		expect(inactivity('assessment_scheduled', daysAgo(1.5), now)).toBeNull();
		expect(inactivity('quote_changes_requested', daysAgo(2), now)?.label).toBe(
			'No progress for 2 days'
		);
	});

	it('never warns a card that has left the board', () => {
		expect(inactivity('request_closed', daysAgo(90), now)).toBeNull();
	});
});
