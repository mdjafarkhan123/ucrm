import { describe, expect, it } from 'vitest';
import { describeMarketingWarmup, type MarketingWarmupProgress } from './warmup';

const warming = (over: Partial<Extract<MarketingWarmupProgress, { status: 'warming' }>> = {}) =>
	({
		status: 'warming',
		step: 2,
		total_steps: 6,
		daily_limit: 250,
		limit_overridden: false,
		sent_today: 120,
		next_daily_limit: 500,
		step_started_at: '2026-09-20T00:00:00Z',
		days_remaining: 1,
		sends_in_step: 100,
		sends_needed: 150,
		quality_ok: true,
		...over
	}) satisfies MarketingWarmupProgress;

describe('describeMarketingWarmup', () => {
	it('shows nothing without a Marketing domain', () => {
		expect(describeMarketingWarmup({ status: 'no_domain' })).toBeNull();
	});

	it('names the limit, the step, today, and what unlocks the next step', () => {
		const card = describeMarketingWarmup(warming())!;
		expect(card.headline).toBe('250 emails a day');
		expect(card.stepLabel).toBe('Step 2 of 6');
		expect(card.today).toEqual({
			sent: 120,
			limit: 250,
			fraction: 0.48,
			label: '120 of 250 sent today'
		});
		expect(card.unlockTitle).toBe('To unlock 500 a day');
		expect(card.requirements.map((r) => [r.key, r.met, r.label])).toEqual([
			['days', false, 'Wait 1 more day'],
			['sends', false, 'Send 150 more emails to real customers'],
			['quality', true, 'Bounces and spam reports are low']
		]);
	});

	it('marks every requirement met once earned', () => {
		const card = describeMarketingWarmup(
			warming({ days_remaining: 0, sends_needed: 0, sends_in_step: 260 })
		)!;
		expect(card.requirements.every((r) => r.met)).toBe(true);
		expect(card.requirements[1].label).toBe('Sent 260 emails on this step');
	});

	it('warns when bounces or complaints hold the step', () => {
		const card = describeMarketingWarmup(warming({ quality_ok: false }))!;
		expect(card.requirements[2].met).toBe(false);
	});

	it('never shows more sent today than the limit', () => {
		expect(describeMarketingWarmup(warming({ sent_today: 400 }))!.today!.fraction).toBe(1);
	});

	it('the last step leads to graduation, not a higher number', () => {
		expect(
			describeMarketingWarmup(warming({ step: 6, daily_limit: 5000, next_daily_limit: null }))!
				.unlockTitle
		).toBe('To finish warming up');
	});

	it('says when support has fixed the limit', () => {
		expect(describeMarketingWarmup(warming({ limit_overridden: true }))!.note).toMatch(/support/);
	});

	it('reports a graduated domain with no daily cap', () => {
		const card = describeMarketingWarmup({
			status: 'graduated',
			step: 7,
			total_steps: 6,
			daily_limit: null,
			sent_today: 30
		})!;
		expect(card.graduated).toBe(true);
		expect(card.today).toBeNull();
		expect(card.step).toBe(6);
	});
});
