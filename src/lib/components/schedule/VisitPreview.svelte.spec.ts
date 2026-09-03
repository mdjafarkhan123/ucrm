import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import VisitPreview from './VisitPreview.svelte';
import type { ScheduleVisit } from '$lib/schedule/api';
import type { TeamMember } from '$lib/team/api';

// The Visit popover on the calendar. Its completion controls invoke the Jobs-owned complete/uncomplete
// command -- Schedule never invents its own completion state (behaviour contract, "Completion and Visit
// outcomes"). This proves the control appears only for a reader who holds the completion authority, that it
// flips with the visit's completed state, and that a completed visit can no longer be rescheduled.

const today = '2026-09-10';

function makeVisit(overrides: Partial<ScheduleVisit> = {}): ScheduleVisit {
	return {
		id: 'visit-1',
		job_id: 'job-1',
		visit_date: '2026-09-10',
		start_time: '09:00',
		end_time: '10:00',
		all_day: false,
		title: 'Fence repair',
		completed_at: null,
		revision: 1,
		position: 0,
		assignee_ids: [],
		job_number: 3,
		job_title: 'Fence repair',
		client_id: 'client-1',
		client_name: 'Colin Reed',
		client_company_name: null,
		property_id: 'prop-1',
		property_label: 'Home',
		property_address_line1: '1 Oak St',
		property_city: 'Austin',
		property_state_region: 'TX',
		property_postal_code: '73301',
		...overrides
	};
}

const employeesById = new Map<string, TeamMember>();

function renderPreview(props: Partial<Parameters<typeof VisitPreview>[1]> = {}) {
	const oncomplete = vi.fn();
	const onuncomplete = vi.fn();
	const onreschedule = vi.fn();
	const onunschedule = vi.fn();
	render(VisitPreview, {
		props: {
			visit: makeVisit(),
			today,
			dayLabel: 'Thu, Sep 10',
			employeesById,
			onreschedule,
			onunschedule,
			oncomplete,
			onuncomplete,
			...props
		}
	});
	return { oncomplete, onuncomplete, onreschedule, onunschedule };
}

describe('VisitPreview completion controls', () => {
	it('hides both completion controls when the reader lacks the authority', async () => {
		renderPreview({ canComplete: false, canSchedule: true });

		await expect.element(page.getByRole('button', { name: 'Reschedule' })).toBeVisible();
		expect(page.getByRole('button', { name: 'Mark complete' }).query()).toBeNull();
		expect(page.getByRole('button', { name: 'Mark incomplete' }).query()).toBeNull();
	});

	it('offers "Mark complete" for an incomplete visit and invokes the Jobs command', async () => {
		const { oncomplete } = renderPreview({ canComplete: true });

		await page.getByRole('button', { name: 'Mark complete' }).click();

		expect(oncomplete).toHaveBeenCalledTimes(1);
		// An incomplete visit shows no "Mark incomplete" undo.
		expect(page.getByRole('button', { name: 'Mark incomplete' }).query()).toBeNull();
	});

	it('offers "Mark incomplete" for a completed visit and invokes the Jobs command', async () => {
		const { onuncomplete } = renderPreview({
			canComplete: true,
			visit: makeVisit({ completed_at: '2026-09-10T12:00:00.000Z' })
		});

		await page.getByRole('button', { name: 'Mark incomplete' }).click();

		expect(onuncomplete).toHaveBeenCalledTimes(1);
		expect(page.getByRole('button', { name: 'Mark complete' }).query()).toBeNull();
	});

	it('never reschedules a completed visit', async () => {
		renderPreview({
			canComplete: true,
			canSchedule: true,
			visit: makeVisit({ completed_at: '2026-09-10T12:00:00.000Z' })
		});

		// A completed visit is frozen: no reschedule, no move-to-unscheduled -- only the undo remains.
		await expect.element(page.getByRole('button', { name: 'Mark incomplete' })).toBeVisible();
		expect(page.getByRole('button', { name: 'Reschedule' }).query()).toBeNull();
		expect(page.getByRole('button', { name: 'Move to Unscheduled' }).query()).toBeNull();
	});
});
