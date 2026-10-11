import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound } from '$lib/server/api/errors';

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
