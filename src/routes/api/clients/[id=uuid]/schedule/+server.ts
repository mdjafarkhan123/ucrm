import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { ClientScheduleEntry } from '$lib/clients/api';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { organizationTimezone } from '$lib/server/requests/timezone';
import { organizationDayRange } from '$lib/server/requests/status';
import { calendarDay } from '$lib/server/time/calendar';

// The client page's Client schedule: this client's visits and on-site assessments — what is coming up, and
// the most recent that has already gone by — the way Jobber's client page shows "upcoming and past scheduled
// visits for this client".
//
// It needs jobs.view, the same authority the Schedule itself asks for, and every row still passes the
// reader's own RLS: an assigned-scope member sees only the visits they are on. Each read reaches the client
// through the job or request it belongs to, walking that table's (organization_id, client_id) index, so its
// cost follows this one client's work, never the organization's whole calendar.
const UPCOMING_LIMIT = 10;
const PAST_LIMIT = 5;

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const clientId = event.params.id;
	const supabase = event.locals.supabase;

	const timezone = await organizationTimezone(organizationId);
	const now = new Date();
	const today = calendarDay(now, timezone);
	// Assessments are booked as instants, so an open one is overdue once it began before the contractor's
	// own midnight today.
	const dayStart = Date.parse(organizationDayRange(timezone, now).day_start);
	const clockFormat = new Intl.DateTimeFormat('en-GB', {
		timeZone: timezone,
		hour: '2-digit',
		minute: '2-digit',
		hourCycle: 'h23'
	});

	// One read for all four lists. public.client_schedule_rows drives every one of them from this client's own
	// jobs and requests (see its migration for why that is not left to a PostgREST embed), returns one more
	// row than asked of each so a full list can tell "exactly at the limit" from "there is more", and runs
	// as the caller, so their RLS still decides which rows they may see.
	const { data, error } = await supabase.rpc('client_schedule_rows', {
		target_organization_id: organizationId,
		target_client_id: clientId,
		upcoming_limit: UPCOMING_LIMIT + 1,
		past_limit: PAST_LIMIT + 1
	});
	if (error) return databaseError();

	// Upcoming is everything booked and not yet done, soonest first, so one dated before today that nobody
	// closed off leads the list flagged Overdue instead of quietly vanishing — the same split the job page's
	// Visits section makes. Past is what has been done, latest first.
	const toEntry = (row: NonNullable<typeof data>[number]): ClientScheduleEntry => {
		const completed = row.completed_at !== null;
		if (row.kind === 'visit') {
			const date: string | null = row.visit_date;
			return {
				kind: 'visit',
				id: row.id,
				record_id: row.record_id,
				date,
				start_time: row.all_day ? null : row.start_time,
				end_time: row.all_day ? null : row.end_time,
				starts_at: null,
				ends_at: null,
				title: row.title || row.record_title || 'Visit',
				record_label: row.job_number === null ? 'Job' : `Job #${row.job_number}`,
				completed,
				overdue: !completed && date !== null && date < today,
				assignee_ids: row.assignee_ids ?? []
			};
		}
		const startsAt: string | null = row.starts_at;
		return {
			kind: 'assessment',
			id: row.id,
			record_id: row.record_id,
			// An assessment is booked as an instant; its day is the day it falls on in the contractor's timezone.
			date: startsAt ? calendarDay(new Date(startsAt), timezone) : null,
			start_time: null,
			end_time: null,
			starts_at: row.all_day ? null : startsAt,
			ends_at: row.all_day ? null : row.ends_at,
			title: row.record_title || 'Assessment',
			record_label: 'Assessment',
			completed,
			overdue: !completed && startsAt !== null && Date.parse(startsAt) < dayStart,
			assignee_ids: row.assignee_ids ?? []
		};
	};

	// Sorted by day, then clock: a visit's plain time and an assessment's instant both reduce to a sortable
	// "YYYY-MM-DD HH:MM" in the contractor's own day.
	const sortKey = (entry: ClientScheduleEntry) => {
		const time = entry.starts_at
			? clockFormat.format(new Date(entry.starts_at))
			: (entry.start_time ?? '');
		return `${entry.date ?? ''} ${time}`;
	};

	const rows = data ?? [];
	const upcomingRows = rows
		.filter((row) => row.bucket === 'upcoming')
		.map(toEntry)
		.sort((a, b) => sortKey(a).localeCompare(sortKey(b)));
	const pastRows = rows
		.filter((row) => row.bucket === 'past')
		.map(toEntry)
		.sort((a, b) => sortKey(b).localeCompare(sortKey(a)));

	return json(
		{
			today,
			timezone,
			upcoming: upcomingRows.slice(0, UPCOMING_LIMIT),
			past: pastRows.slice(0, PAST_LIMIT),
			has_more_upcoming: upcomingRows.length > UPCOMING_LIMIT,
			has_more_past: pastRows.length > PAST_LIMIT
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
