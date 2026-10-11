import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import JobVisitsSection from './JobVisitsSection.svelte';
import type { JobRecurrenceInput, JobVisit } from '$lib/jobs/api';
import { myTimerKey, type MyTimer } from '$lib/time-clock/api';
import { visitChecklistsKey } from '$lib/checklists/api';
import { assignableTeamKey } from '$lib/team/api';

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
		completed_by_name: null,
		series_date: null,
		off_series: false,
		revision: 1,
		assignee_ids: [],
		invoiced: false,
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

// The card's reads are seeded so it never asks a server these browser tests do not have: `timer` is the
// reader's own timer, as /api/time-clock/timer would answer (by default they may not time, so no timer control
// shows), and each row's hover warm-up finds its team list and checklists already loaded.
const cannotTime: MyTimer = {
	timer: null,
	clocked_in: false,
	can_time: false,
	server_now: new Date().toISOString()
};

function renderSection(props: Partial<Props> = {}, timer: MyTimer = cannotTime) {
	const queryClient = createQueryClient();
	queryClient.setQueryData(myTimerKey, timer);
	queryClient.setQueryData(assignableTeamKey, []);
	for (const visit of props.visits ?? []) {
		queryClient.setQueryData(visitChecklistsKey(visit.id), {
			checklists: [],
			outstanding_required: 0,
			can_answer: false
		});
	}
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
				priceBasis: 'job_total',
				billingTiming: 'on_closure',
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
		makeVisit({
			title: 'Done One',
			visit_date: '2026-08-01',
			completed_at: '2026-08-01T12:00:00Z'
		}),
		makeVisit({
			title: 'Done Two',
			visit_date: '2026-08-02',
			completed_at: '2026-08-02T12:00:00Z'
		}),
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

	it('names who completed a past visit, and only the date when the name is unknown', async () => {
		renderSection({
			visits: [
				makeVisit({ title: 'Next', visit_date: '2026-12-01' }),
				makeVisit({
					title: 'Named',
					visit_date: '2026-08-01',
					completed_at: '2026-08-01T12:00:00Z',
					completed_by_name: 'Sam Carter'
				}),
				makeVisit({
					title: 'Unnamed',
					visit_date: '2026-08-02',
					completed_at: '2026-08-02T12:00:00Z'
				})
			]
		});

		await page.getByRole('button', { name: /^Past/ }).click();

		await expect.element(page.getByText(/^Completed .* by Sam Carter$/)).toBeVisible();
		expect(page.getByText(/by/).elements()).toHaveLength(1);
	});

	it('marks a visit that left its repeat series and leaves the others plain', async () => {
		renderSection({
			jobType: 'recurring',
			recurrence: weeklyOnMonday,
			visits: [
				makeVisit({ title: 'On series', visit_date: '2026-09-14', series_date: '2026-09-14' }),
				makeVisit({
					title: 'Moved',
					visit_date: '2026-09-16',
					series_date: '2026-09-21',
					off_series: true
				}),
				makeVisit({
					title: 'Own time',
					visit_date: '2026-09-28',
					series_date: '2026-09-28',
					start_time: '15:00:00',
					all_day: false,
					off_series: true
				})
			]
		});

		await expect.element(page.getByText(/Originally /)).toBeVisible();
		await expect.element(page.getByText('Time changed for this visit only')).toBeVisible();
		expect(
			page.getByTitle("This visit no longer follows the job's repeat schedule.").elements()
		).toHaveLength(2);
	});
});

// Time clock Part 2 (docs/time-clock-behavior-contract.md § Timers): each open visit row offers the reader's
// own Start, the visit a timer runs on shows it ticking with Stop, and a timer on another job is named once.
describe('JobVisitsSection visit timers', () => {
	const serverNow = new Date().toISOString();
	const noTimer: MyTimer = {
		timer: null,
		clocked_in: false,
		can_time: true,
		server_now: serverNow
	};

	function runningOn(jobId: string, visitId: string, jobNumber = 20): MyTimer {
		return {
			timer: {
				kind: 'visit',
				job_id: jobId,
				job_number: jobNumber,
				job_title: 'Deck repair',
				visit_id: visitId,
				visit_date: '2026-09-10',
				started_at: new Date(Date.now() - 42 * 60_000).toISOString(),
				day_clock_paused: false
			},
			clocked_in: false,
			can_time: true,
			server_now: serverNow
		};
	}

	it('offers Start on each open visit and not on a completed one', async () => {
		renderSection(
			{
				visits: [
					makeVisit({ title: 'Open', visit_date: '2026-09-10' }),
					makeVisit({
						title: 'Done',
						visit_date: '2026-08-01',
						completed_at: '2026-08-01T12:00:00Z'
					})
				]
			},
			noTimer
		);

		await expect.element(page.getByRole('button', { name: 'Start timer' })).toBeVisible();
		await page.getByRole('button', { name: /Past/ }).click();
		await expect.element(page.getByText('Done', { exact: false })).toBeVisible();
		expect(page.getByRole('button', { name: 'Start timer' }).elements()).toHaveLength(1);
	});

	it('offers no Start to someone who may not time their work', async () => {
		renderSection({ visits: [makeVisit({ title: 'Open' })] }, { ...noTimer, can_time: false });
		await expect.element(page.getByText('Open', { exact: false })).toBeVisible();
		expect(page.getByRole('button', { name: 'Start timer' }).query()).toBeNull();
	});

	it('offers no Start on a closed job', async () => {
		renderSection({ visits: [makeVisit({ title: 'Open' })], jobStatus: 'closed' }, noTimer);
		await expect.element(page.getByText('Open', { exact: false })).toBeVisible();
		expect(page.getByRole('button', { name: 'Start timer' }).query()).toBeNull();
	});

	it('shows the running timer with Stop on its visit, and no Start on the others', async () => {
		const running = makeVisit({ title: 'Running here', visit_date: '2026-09-10' });
		renderSection(
			{ visits: [running, makeVisit({ title: 'Other', visit_date: '2026-09-11' })] },
			runningOn('job-1', running.id)
		);

		await expect.element(page.getByRole('button', { name: 'Stop timer' })).toBeVisible();
		await expect.element(page.getByText(/^0:42:\d\d$/)).toBeVisible();
		expect(page.getByRole('button', { name: 'Start timer' }).query()).toBeNull();
	});

	it('names a timer running on another job once, instead of offering Start', async () => {
		renderSection(
			{
				visits: [
					makeVisit({ title: 'One', visit_date: '2026-09-10' }),
					makeVisit({ title: 'Two', visit_date: '2026-09-11' })
				]
			},
			runningOn('job-2', 'visit-elsewhere', 21)
		);

		await expect.element(page.getByRole('link', { name: 'Job #21' })).toBeVisible();
		expect(page.getByText(/Your timer is running on/).elements()).toHaveLength(1);
		expect(page.getByRole('button', { name: 'Start timer' }).query()).toBeNull();
	});

	// Time clock Part 3: the day clock is not a visit timer. While clocked in, every open visit still offers
	// Start, and starting one pauses the day clock.
	it('still offers Start while the day clock runs', async () => {
		renderSection(
			{ visits: [makeVisit({ title: 'Open', visit_date: '2026-09-10' })] },
			{
				timer: {
					kind: 'general',
					job_id: null,
					job_number: null,
					job_title: null,
					visit_id: null,
					visit_date: null,
					started_at: new Date(Date.now() - 90 * 60_000).toISOString(),
					day_clock_paused: false
				},
				clocked_in: true,
				can_time: true,
				server_now: serverNow
			}
		);

		await expect.element(page.getByRole('button', { name: 'Start timer' })).toBeVisible();
		expect(page.getByText(/Your timer is running on/).query()).toBeNull();
	});
});
