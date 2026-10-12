import { timesheetsKey } from '$lib/time-clock/timesheets';

// Weekly approval (docs/time-clock-behavior-contract.md § Weekly approval). A manager approves every stopped
// entry up to and including a day, for the people they choose. Running timers are never approved; they are
// listed so they can be stopped first.

export type ApprovalPerson = {
	user_id: string;
	name: string | null;
	status: 'pending' | 'active' | 'deactivated' | 'removed' | null;
	is_me: boolean;
	/** Stopped entries waiting, up to and including the day. */
	entry_count: number;
	minutes: number;
	/** The earliest day with hours waiting. Older weeks left unapproved show up here too. */
	first_day: string;
};

export type ApprovalRunningTimer = {
	user_id: string;
	name: string | null;
	kind: 'visit' | 'general' | 'assessment';
	job_number: number | null;
	started_at: string;
	started_on: string;
	over_a_day: boolean;
};

export type ApprovalPreview = {
	cutoff: string;
	today: string;
	timezone: string;
	people: ApprovalPerson[];
	running: ApprovalRunningTimer[];
};

export type ApprovalResult = {
	cutoff: string;
	approved_count: number;
	approved_minutes: number;
	people_count: number;
	/** The chosen people's timers still running, never approved. */
	running: ApprovalRunningTimer[];
};

export type ApprovalError = Error & { status?: number };

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(() => ({}) as { error?: string; field_errors?: Record<string, string> });
		const fieldErrors = result.field_errors as Record<string, string> | undefined;
		const message = fieldErrors
			? (fieldErrors.form ?? Object.values(fieldErrors)[0] ?? result.error)
			: result.error;
		const error = new Error(message ?? fallback) as ApprovalError;
		error.status = response.status;
		throw error;
	}
	return response.json();
}

// Under Timesheets, so a timer stopping or an entry changing refreshes what is waiting too.
export const approvalPreviewKey = (cutoff: string) =>
	[...timesheetsKey, 'approval', cutoff] as const;

export async function fetchApprovalPreview(cutoff: string): Promise<ApprovalPreview> {
	const response = await fetch(
		`/api/time-clock/timesheets/approval?${new URLSearchParams({ date: cutoff })}`
	);
	return readOrThrow(response, 'What is waiting for approval could not be loaded.');
}

export async function approveTimesheets(
	cutoff: string,
	userIds: string[]
): Promise<ApprovalResult> {
	const response = await fetch('/api/time-clock/timesheets/approval', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ cutoff, user_ids: userIds })
	});
	return readOrThrow(response, 'The hours were not approved. Try again.');
}

/**
 * The day the dialog starts on: the last day of the window being looked at, or today when that is still to
 * come. Approving last week means stepping back a week and pressing Approve.
 */
export function defaultCutoff(windowEnd: string, today: string) {
	return windowEnd < today ? windowEnd : today;
}

/** "Approved 12 entries for 3 people", and what was left running. */
export function approvalMessage(result: ApprovalResult) {
	if (result.approved_count === 0) return 'Nothing was waiting for approval.';
	const entries = result.approved_count === 1 ? '1 entry' : `${result.approved_count} entries`;
	const people = result.people_count === 1 ? '1 person' : `${result.people_count} people`;
	const running =
		result.running.length === 0
			? ''
			: result.running.length === 1
				? ' 1 running timer was not approved.'
				: ` ${result.running.length} running timers were not approved.`;
	return `Approved ${entries} for ${people}.${running}`;
}
