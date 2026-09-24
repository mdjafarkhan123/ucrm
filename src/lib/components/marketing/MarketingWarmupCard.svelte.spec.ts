import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import MarketingWarmupCard from './MarketingWarmupCard.svelte';
import { describeMarketingWarmup, type MarketingWarmupProgress } from '$lib/marketing/warmup';

const warming: MarketingWarmupProgress = {
	status: 'warming',
	step: 1,
	total_steps: 6,
	daily_limit: 100,
	limit_overridden: false,
	sent_today: 40,
	next_daily_limit: 250,
	step_started_at: '2026-09-23T00:29:51.997Z',
	days_remaining: 2,
	sends_in_step: 2,
	sends_needed: 98,
	quality_ok: true
};

function renderCard(progress: MarketingWarmupProgress) {
	const card = describeMarketingWarmup(progress);
	if (!card) throw new Error('expected a card');
	return render(MarketingWarmupCard, { card });
}

describe('MarketingWarmupCard', () => {
	it('shows the step, today’s use, and what unlocks the next step', async () => {
		renderCard(warming);

		await expect.element(page.getByRole('heading', { name: 'Sending warm-up' })).toBeVisible();
		await expect.element(page.getByText('100 emails a day')).toBeVisible();
		await expect.element(page.getByText('Step 1 of 6', { exact: true }).first()).toBeVisible();

		const meter = page.getByRole('progressbar', { name: 'Marketing emails sent today' });
		await expect.element(meter).toHaveAttribute('aria-valuenow', '40');
		await expect.element(meter).toHaveAttribute('aria-valuemax', '100');

		await expect.element(page.getByText('To unlock 250 a day')).toBeVisible();
		await expect.element(page.getByText('Wait 2 more days')).toBeVisible();
		await expect.element(page.getByText('Send 98 more emails to real customers')).toBeVisible();
		await expect.element(page.getByText('Bounces and spam reports are low')).toBeVisible();

		const current = document.querySelector('[aria-current="step"]');
		expect(current?.textContent).toContain('Step 1');
		expect(document.querySelectorAll('.warmup__rung--next')).toHaveLength(5);
	});

	it('shows a finished warm-up without a limit or checklist', async () => {
		renderCard({ status: 'graduated', step: 7, total_steps: 6, daily_limit: null, sent_today: 12 });

		await expect.element(page.getByText('Fully warmed up')).toBeVisible();
		await expect.element(page.getByText('All 6 steps complete')).toBeVisible();
		expect(page.getByRole('progressbar').elements()).toHaveLength(0);
		expect(page.getByText(/To unlock/).elements()).toHaveLength(0);
	});
});
