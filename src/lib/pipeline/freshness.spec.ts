import { describe, expect, it } from 'vitest';
import { DEFAULT_INACTIVITY_DAYS, inactivity, stageAge, type InactivityRules } from './freshness';
import type { CustomStage } from './stages';

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

const rules: InactivityRules = {
	days: DEFAULT_INACTIVITY_DAYS,
	customStages: [],
	today: '2026-10-01'
};

type Card = Parameters<typeof inactivity>[0];
const card = (stage: Card['stage'], progressAt: string, extra: Partial<Card> = {}): Card => ({
	stage,
	custom_stage_id: null,
	progress_at: progressAt,
	task: null,
	...extra
});

const onHold: CustomStage = {
	id: '11111111-1111-4111-8111-111111111111',
	section: 'quote',
	name: 'Waiting till spring',
	after_stage: 'quote_awaiting_response',
	requires_future_task: true,
	inactivity_days: 3
};

describe('inactivity', () => {
	it('warns a New request untouched for two days', () => {
		expect(inactivity(card('new_request', daysAgo(2)), rules, now)).toEqual({
			days: 2,
			label: 'No progress for 2 days'
		});
	});

	it('stays quiet inside the stage limit', () => {
		expect(inactivity(card('new_request', daysAgo(0.9)), rules, now)).toBeNull();
		expect(inactivity(card('quote_awaiting_response', daysAgo(4.9)), rules, now)).toBeNull();
		expect(inactivity(card('quote_awaiting_response', daysAgo(5)), rules, now)?.days).toBe(5);
	});

	it('uses each stage’s own default', () => {
		expect(inactivity(card('assessment_scheduled', daysAgo(1.5)), rules, now)).toBeNull();
		expect(inactivity(card('quote_changes_requested', daysAgo(2)), rules, now)?.label).toBe(
			'No progress for 2 days'
		);
	});

	it('follows the owner’s own days for a built-in stage', () => {
		const owned = { ...rules, days: { ...DEFAULT_INACTIVITY_DAYS, quote_awaiting_response: 3 } };
		expect(inactivity(card('quote_awaiting_response', daysAgo(3)), owned, now)?.days).toBe(3);
		expect(inactivity(card('quote_awaiting_response', daysAgo(2.9)), owned, now)).toBeNull();
	});

	it('uses a custom stage’s own days', () => {
		const followUp = { ...onHold, requires_future_task: false, inactivity_days: 10 };
		const placed = card('quote_awaiting_response', daysAgo(7), { custom_stage_id: followUp.id });
		expect(inactivity(placed, { ...rules, customStages: [followUp] }, now)).toBeNull();
		expect(
			inactivity(
				{ ...placed, progress_at: daysAgo(10) },
				{ ...rules, customStages: [followUp] },
				now
			)?.days
		).toBe(10);
	});

	it('keeps an on-hold card quiet until its Task falls due', () => {
		const withHold = { ...rules, customStages: [onHold] };
		const held = (dueOn: string | null) =>
			card('quote_awaiting_response', daysAgo(40), {
				custom_stage_id: onHold.id,
				task: { due_on: dueOn }
			});
		expect(inactivity(held('2026-10-02'), withHold, now)).toBeNull();
		expect(inactivity(held('2026-10-01'), withHold, now)?.days).toBe(40);
		expect(inactivity(held(null), withHold, now)?.days).toBe(40);
	});

	it('never warns a card that has left the board, or before the rules arrive', () => {
		expect(inactivity(card('request_closed', daysAgo(90)), rules, now)).toBeNull();
		expect(inactivity(card('new_request', daysAgo(90)), null, now)).toBeNull();
	});
});
