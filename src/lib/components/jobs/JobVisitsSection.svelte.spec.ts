import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import JobVisitsSection from './JobVisitsSection.svelte';
import type { JobRecurrenceInput, JobVisit } from '$lib/jobs/api';

// The Job detail Visits card mirrors Jobber's grouped card (behaviour contract, "Job detail Visits card"):
// To be scheduled / Upcoming / Past, only the next three Upcoming until "Show all", Past collapsed by
// default, a recurrence summary for a repeating job, and an as-needed job read apart from an empty one.

function makeVisit(overrides: Partial<JobVisit> = {}): JobVisit {
	return {
		id: crypto.randomUUID(),
		position: 0,
		visit_date: '2026-09-10',
		start_time: null,
		end_time: null,
		all_day: true,
		title: null,
		instructions: null,
		completed_at: null,
		revision: 1,
		assignee_ids: [],
		...overrides
	};
}

const weeklyOnMonday: JobRecurrenceInput = {
	frequency: 'weekly',
	interval_count: 1,
	weekdays: [1],
	monthly_mode: null,
	month_day: null,
	ordinal_week: null,
	ordinal_weekday: null,
	start_date: '2026-01-05',
	end_mode: 'after',
	duration_count: 8,
	duration_unit: 'week',
	end_date: null,
	start_time: null,
	end_time: null,
	all_day: true
};

type Props = Parameters<typeof JobVisitsSection>[1];

function renderSection(props: Partial<Props> = {}) {
	const queryClient = createQueryClient();
	render(
		JobVisitsSection,
		{
			props: {
				jobId: 'job-1',
				visits: [],
				canSchedule: true,
				canComplete: true,
				canClose: true,
				jobStatus: 'active',
				jobType: 'one_off',
				isAsNeeded: false,
				recurrence: null,
				jobRevision: 1,
				...props
			} as Props
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
}

// Five future incomplete visits (Upcoming), two completed (Past), one dateless (To be scheduled).
function mixedVisits(): JobVisit[] {
	return [
		makeVisit({ title: 'Up A', visit_date: '2026-09-10' }),
		makeVisit({ title: 'Up B', visit_date: '2026-09-11' }),
		makeVisit({ title: 'Up C', visit_date: '2026-09-12' }),
		makeVisit({ title: 'Up D', visit_date: '2026-09-13' }),
		makeVisit({ title: 'Up E', visit_date: '2026-09-14' }),
		makeVisit({ title: 'Done One', visit_date: '2026-08-01', completed_at: '2026-08-01T12:00:00Z' }),
		makeVisit({ title: 'Done Two', visit_date: '2026-08-02', completed_at: '2026-08-02T12:00:00Z' }),
		makeVisit({ title: 'Later One', visit_date: null })
	];
}

describe('JobVisitsSection grouped card', () => {
	it('groups visits into To be scheduled, Upcoming and Past', async () => {
		renderSection({ visits: mixedVisits() });

		await expect.element(page.getByText(/^To be scheduled/)).toBeVisible();
		await expect.element(page.getByText(/^Upcoming/)).toBeVisible();
		await expect.element(page.getByRole('button', { name: /Past/ })).toBeVisible();
		await expect.element(page.getByText('Later One', { exact: false })).toBeVisible();
	});

	it('shows only the next three Upcoming visits until "Show all" is used', async () => {
		renderSection({ visits: mixedVisits() });

		// Earliest three are visible; the later two are hidden behind the disclosure.
		await expect.element(page.getByText('Up A', { exact: false })).toBeVisible();
		await expect.element(page.getByText('Up C', { exact: false })).toBeVisible();
		expect(page.getByText('Up D', { exact: false }).query()).toBeNull();

		await page.getByRole('button', { name: /Show all 5 upcoming visits/ }).click();

		await expect.element(page.getByText('Up D', { exact: false })).toBeVisible();
		await expect.element(page.getByText('Up E', { exact: false })).toBeVisible();
	});

	it('collapses Past by default and reveals it on toggle', async () => {
		renderSection({ visits: mixedVisits() });

		expect(page.getByText('Done One', { exact: false }).query()).toBeNull();

		await page.getByRole('button', { name: /^Past/ }).click();

		await expect.element(page.getByText('Done One', { exact: false })).toBeVisible();
		await expect.element(page.getByText('Done Two', { exact: false })).toBeVisible();
	});

	it('shows a recurrence summary with count for a recurring job', async () => {
		renderSection({
			jobType: 'recurring',
			isAsNeeded: false,
			recurrence: weeklyOnMonday,
			visits: [
				makeVisit({ title: 'Wk 1', visit_date: '2026-09-07' }),
				makeVisit({ title: 'Wk 2', visit_date: '2026-09-14' })
			]
		});

		await expect.element(page.getByText('Weekly on Monday')).toBeVisible();
		await expect.element(page.getByText('2 visits', { exact: false })).toBeVisible();
	});

	it('distinguishes an as-needed job from an accidentally empty one', async () => {
		renderSection({ isAsNeeded: true, visits: [] });

		await expect.element(page.getByText('Dispatched as needed')).toBeVisible();
	});
});
