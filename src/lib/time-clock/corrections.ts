import type { QueryClient } from '@tanstack/svelte-query';
import { durationLabel, myTimerKey } from '$lib/time-clock/api';
import { clockTime, timesheetsKey, type TimesheetEntry } from '$lib/time-clock/timesheets';
import { formatCalendarDay } from '$lib/schedule/labels';

// Time clock Part 5 (docs/time-clock-behavior-contract.md § Timesheets page, § Forgotten timers): adding,
// correcting and removing hours from Timesheets, an entry's edit history, and the manager's clock in and stop
// at the real end time. Times travel as the business's own clock (a day and HH:MM); the server turns them into
// instants in the business's time zone.

export type CorrectionError = Error & { status?: number; fieldErrors?: Record<string, string> };

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(() => ({}) as { error?: string; field_errors?: Record<string, string> });
		// A form error carries the database's own sentence ("A single entry cannot be longer than 24 hours.")
		// under field_errors.form; show that rather than the generic "review the fields".
		const fieldErrors = result.field_errors as Record<string, string> | undefined;
		const message = fieldErrors
			? (fieldErrors.form ?? Object.values(fieldErrors)[0] ?? result.error)
			: result.error;
		const error = new Error(message ?? fallback) as CorrectionError;
		error.status = response.status;
		error.fieldErrors = fieldErrors;
		throw error;
	}
	return response.json();
}

function send(url: string, method: string, body?: unknown) {
	return fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
}

export type PickedJob = { id: string; job_number: number; title: string };

/** What the Timesheets entry dialog is open for. A running timer changes only its start and notes. */
export type EntryDialogMode =
	| { kind: 'add'; userId: string; day: string }
	| { kind: 'edit'; entry: TimesheetEntry; userId: string }
	| { kind: 'running'; entry: TimesheetEntry; userId: string };

/** An entry as the Timesheets form writes it. No job means General time. */
export type TimesheetEntryInput = {
	user_id: string;
	job_id: string | null;
	visit_id: string | null;
	/** YYYY-MM-DD, the business's day the work started. */
	day: string;
	/** HH:MM on the business's clock. An end at or before the start is the next morning. */
	start_time: string;
	end_time: string;
	notes: string | null;
};

export async function addTimesheetEntry(input: TimesheetEntryInput) {
	const response = await send('/api/time-clock/timesheets/entries', 'POST', input);
	return readOrThrow<{ id: string }>(response, 'The hours were not saved. Try again.');
}

export async function updateTimesheetEntry(entryId: string, input: TimesheetEntryInput) {
	const response = await send(`/api/time-clock/timesheets/entries/${entryId}`, 'PATCH', input);
	return readOrThrow<{ id: string; changed: boolean }>(
		response,
		'The hours were not saved. Try again.'
	);
}

export async function deleteTimesheetEntry(entryId: string) {
	const response = await send(`/api/time-clock/timesheets/entries/${entryId}`, 'DELETE');
	return readOrThrow<{ id: string }>(response, 'The entry was not deleted. Try again.');
}

/** While a timer runs only its start and notes change. */
export async function updateRunningTimer(
	userId: string,
	input: { day: string; start_time: string; notes: string | null }
) {
	const response = await send(`/api/time-clock/timesheets/running/${userId}`, 'PATCH', input);
	return readOrThrow<{ id: string; changed: boolean }>(
		response,
		'The timer was not changed. Try again.'
	);
}

/** Clock out now, or stop at the day and time work really ended. Nothing resumes afterwards. */
export async function stopTimerAt(userId: string, end: { day: string; time: string } | null) {
	const response = await send(
		`/api/time-clock/timesheets/running/${userId}/stop`,
		'POST',
		end ?? {}
	);
	return readOrThrow<{ stopped: boolean; recorded: boolean; too_short?: boolean }>(
		response,
		'The timer did not stop. Check your connection and try again.'
	);
}

export async function clockInMember(userId: string) {
	const response = await send(`/api/time-clock/timesheets/running/${userId}/clock-in`, 'POST');
	return readOrThrow<{ clocked_in: true; paused_by_visit: boolean }>(
		response,
		'They were not clocked in. Check your connection and try again.'
	);
}

/** What a person's entry list can ask the Timesheets page to open. */
export type TimesheetEntryActions = {
	edit: (entry: TimesheetEntry, userId: string) => void;
	stop: (entry: TimesheetEntry, userId: string) => void;
	history: (entry: TimesheetEntry) => void;
	remove: (entry: TimesheetEntry, userId: string) => void;
	/** The entry's menu was pointed at: start reading its history. */
	warm: (entry: TimesheetEntry) => void;
};

/** Whose timer the stop dialog ends, and what it says about it. */
export type StopTarget = {
	userId: string;
	/** "Sam Lee", or "you". */
	name: string;
	startedAt: string;
	clockedIn: boolean;
	overADay: boolean;
	/** "Job #20" or "General". */
	what: string;
};

// --- Edit history ----------------------------------------------------------------------------------------

export type HistoryValues = {
	kind: 'job' | 'general';
	user_id: string;
	user_name: string | null;
	job_id: string | null;
	job_number: number | null;
	visit_id: string | null;
	visit_date: string | null;
	started_at: string;
	/** Null while the timer was still running. */
	minutes: number | null;
	/** Absent for hours recorded before the history existed, whose notes were never kept. */
	notes?: string | null;
};

export type HistoryEvent = {
	id: string;
	action: 'added' | 'stopped' | 'changed' | 'deleted';
	at: string;
	actor_name: string | null;
	is_me: boolean;
	prior: HistoryValues | null;
	new: HistoryValues | null;
};

export type EntryHistory = { entry_id: string; timezone: string; events: HistoryEvent[] };

export const entryHistoryKey = (entryId: string) => [...timesheetsKey, 'history', entryId] as const;

export async function fetchEntryHistory(entryId: string): Promise<EntryHistory> {
	const response = await fetch(`/api/time-clock/timesheets/entries/${entryId}/history`);
	return readOrThrow(response, 'The history could not be loaded.');
}

function purpose(values: HistoryValues) {
	if (values.kind === 'general') return 'General';
	return values.job_number === null ? 'a Job' : `Job #${values.job_number}`;
}

function when(values: HistoryValues, timezone: string) {
	const day = new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(
		new Date(values.started_at)
	);
	const start = clockTime(values.started_at, timezone);
	const dayLabel = formatCalendarDay(day, { month: 'short', day: 'numeric' });
	if (values.minutes === null) return `${dayLabel}, from ${start}`;
	const end = clockTime(
		new Date(Date.parse(values.started_at) + values.minutes * 60_000).toISOString(),
		timezone
	);
	return `${dayLabel}, ${start} – ${end}`;
}

/** Who did it, in a few words: "Added by Sam", "Changed by you". */
export function historyHeadline(event: HistoryEvent) {
	const who = event.is_me ? 'you' : (event.actor_name ?? 'someone who has left');
	const verb = {
		added: 'Added',
		stopped: 'Timer stopped',
		changed: 'Changed',
		deleted: 'Deleted'
	}[event.action];
	return `${verb} by ${who}`;
}

/**
 * What one history event changed, a line per field: "Time: Oct 5, 8:00 AM – 12:00 PM → Oct 5, 7:30 AM –
 * 12:00 PM". An addition or a stop lists what the entry was; a deletion what it had been.
 */
export function historyLines(event: HistoryEvent, timezone: string): string[] {
	const before = event.prior;
	const after = event.new;
	if (!before || !after) {
		const values = after ?? before;
		if (!values) return [];
		const lines = [
			`Person: ${values.user_name ?? 'a former team member'}`,
			`For: ${purpose(values)}`,
			`Time: ${when(values, timezone)}`
		];
		if (values.minutes !== null) lines.push(`Duration: ${durationLabel(values.minutes)}`);
		if (values.notes) lines.push(`Notes: ${values.notes}`);
		return lines;
	}

	const lines: string[] = [];
	if (before.user_id !== after.user_id) {
		lines.push(
			`Person: ${before.user_name ?? 'a former team member'} → ${after.user_name ?? 'a former team member'}`
		);
	}
	if (before.kind !== after.kind || before.job_id !== after.job_id) {
		lines.push(`For: ${purpose(before)} → ${purpose(after)}`);
	} else if (before.visit_id !== after.visit_id) {
		lines.push(after.visit_id ? 'Visit changed' : 'Visit removed');
	}
	if (before.started_at !== after.started_at || before.minutes !== after.minutes) {
		lines.push(`Time: ${when(before, timezone)} → ${when(after, timezone)}`);
	}
	// Notes written before the history existed were never kept, so an unknown "before" says only what they
	// became.
	if ('notes' in before && 'notes' in after && (before.notes ?? '') !== (after.notes ?? '')) {
		if (!after.notes) lines.push('Notes removed');
		else
			lines.push(
				before.notes
					? `Notes: “${before.notes}” → “${after.notes}”`
					: `Notes added: “${after.notes}”`
			);
	}
	return lines;
}

// Everything a correction can change: Timesheets, the person's own running timer (a manager may have stopped
// or started it), and Job Labor and costing for whichever Jobs the hours left or joined.
export async function refreshAfterCorrection(queryClient: QueryClient) {
	await Promise.all([
		queryClient.invalidateQueries({ queryKey: timesheetsKey }),
		queryClient.invalidateQueries({ queryKey: myTimerKey }),
		queryClient.invalidateQueries({ queryKey: ['jobs', 'labor'] }),
		queryClient.invalidateQueries({ queryKey: ['jobs', 'detail'] })
	]);
}

// --- The form's clock ------------------------------------------------------------------------------------

/** An instant as the business's day and HH:MM, the way the correction form holds it. */
export function businessClock(instant: string | number | Date, timezone: string) {
	const parts = new Intl.DateTimeFormat('en-CA', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit',
		hour: '2-digit',
		minute: '2-digit',
		hourCycle: 'h23'
	}).formatToParts(new Date(instant));
	const part = (type: string) => parts.find((entry) => entry.type === type)?.value ?? '00';
	return {
		day: `${part('year')}-${part('month')}-${part('day')}`,
		time: `${part('hour')}:${part('minute')}`
	};
}

/** Minutes from a start to an end clock time; an end at or before the start is the next morning. */
export function spanMinutes(start: string, end: string) {
	const toMinutes = (time: string) => {
		const [hours, minutes] = time.split(':').map(Number);
		return hours * 60 + minutes;
	};
	const span = (toMinutes(end) - toMinutes(start) + 1440) % 1440;
	return span === 0 ? 1440 : span;
}
