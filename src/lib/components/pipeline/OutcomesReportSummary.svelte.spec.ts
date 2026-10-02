import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import OutcomesReportSummary from './OutcomesReportSummary.svelte';
import type { OutcomesReport } from '$lib/pipeline/api';

const base: OutcomesReport = {
	won: { count: 3, unvalued_count: 1, value_total: 900 },
	lost: { count: 4, unvalued_count: 0, value_total: 400 },
	direct_job: { count: 2, unvalued_count: 2, value_total: null },
	days_to_win: { count: 3, median: 5, average: 6.5 },
	lost_reasons: [
		{ reason: 'price_too_high', label: 'Price too high', count: 3 },
		{ reason: null, label: 'No reason given', count: 1 }
	],
	can_view_value: true,
	currency_code: 'CAD',
	locale: 'en-CA',
	timezone: 'America/Toronto'
};

describe('OutcomesReportSummary', () => {
	it('shows each Lost reason with its count, and Direct jobs apart from Won', async () => {
		render(OutcomesReportSummary, { props: { report: base } });

		await expect.element(page.getByText('Why deals were lost')).toBeVisible();
		await expect.element(page.getByText('Price too high')).toBeVisible();
		await expect.element(page.getByText('No reason given')).toBeVisible();
		await expect.element(page.getByText('75%')).toBeVisible();
		await expect.element(page.getByText('Direct jobs')).toBeVisible();
		await expect.element(page.getByText(/Counted apart from Won/)).toBeVisible();
	});

	it('labels missing values Unvalued instead of zero', async () => {
		render(OutcomesReportSummary, { props: { report: base } });

		await expect.element(page.getByText(/1 unvalued/)).toBeVisible();
		await expect.element(page.getByText(/Counted apart from Won · Unvalued/)).toBeVisible();
	});

	it('shows median and average days to win', async () => {
		render(OutcomesReportSummary, { props: { report: base } });

		await expect.element(page.getByText('5 days', { exact: true })).toBeVisible();
		await expect.element(page.getByText('Median · average 6.5 days')).toBeVisible();
	});

	it('shows a dash, not zero days, when nothing was won, and hides the reasons when nothing was lost', async () => {
		render(OutcomesReportSummary, {
			props: {
				report: {
					...base,
					won: { count: 0, unvalued_count: 0, value_total: null },
					lost: { count: 0, unvalued_count: 0, value_total: null },
					days_to_win: { count: 0, median: null, average: null },
					lost_reasons: []
				}
			}
		});

		await expect.element(page.getByText('Nothing won in this period')).toBeVisible();
		await expect.element(page.getByText('Why deals were lost')).not.toBeInTheDocument();
	});

	it('shows no money to a member without value access', async () => {
		render(OutcomesReportSummary, {
			props: {
				report: {
					...base,
					can_view_value: false,
					won: { count: 3, unvalued_count: 0 },
					lost: { count: 4, unvalued_count: 0 },
					direct_job: { count: 2, unvalued_count: 0 }
				}
			}
		});

		await expect.element(page.getByText(/\$/)).not.toBeInTheDocument();
	});
});
