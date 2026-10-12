import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// The timer commands (`start_visit_timer`, `stop_my_timer`) refuse in these shapes. A member who may not time
// the job, or a job in another business, is insufficient_privilege and reads as not found — a stranger cannot
// tell which. A second timer is a conflict the person resolves by stopping the first. A closed job, a
// completed visit or a timer over a day is a rule, carrying the sentence the database already wrote.
export function timerError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That visit could not be found.');
	if (error.code === 'P0404') return notFound(error.message ?? 'That visit could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error:
					error.message ?? 'You already have a timer running. Stop it before starting another.',
				reason: 'timer_running'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === 'P0410')
		return json(
			{ error: error.message ?? 'This timer cannot be changed.', reason: 'locked' },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	return databaseError();
}

// Timesheets corrections (`add_time_entry`, `update_time_entry`, `delete_time_entry`, `update_running_timer`,
// `stop_timer_at`, `clock_in_member`, `time_entry_history`). Someone without access is told so plainly here:
// they are looking at the entry on their own Timesheets, so there is nothing to hide about whether it exists.
// A rule (a closed Job, a running timer, over a day) is a conflict carrying the database's sentence; times
// that cannot make an entry are a form error.
export function timesheetWriteError(error: DatabaseError) {
	if (error.code === '42501')
		return json(
			{ error: error.message ?? 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	if (error.code === 'P0404') return notFound(error.message ?? 'Those hours could not be found.');
	if (error.code === 'P0409' || error.code === 'P0410')
		return json(
			{ error: error.message ?? 'These hours cannot be changed.', reason: 'locked' },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '22023' || error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'Those hours cannot be saved as entered.' });
	return databaseError();
}
