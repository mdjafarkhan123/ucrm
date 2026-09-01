import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';

const JOB_NOT_FOUND = 'That client or property could not be found.';

type DatabaseError = { code?: string; message?: string };

// `create_job_with_visits` refuses in four ways, and each raise already carries the sentence a person
// should read. A member without jobs.create, and a client or property belonging to another organization,
// both come back as insufficient_privilege — a stranger learns nothing either way. A repeated idempotency
// key carrying different details is a conflict, not a reload prompt: the browser sends the person to the
// job that already started. The table's own checks (a bad line, too many visits) and its foreign keys (a
// property that is not this client's, an assignee who is not a member) surface as a form error rather than
// a raw constraint violation.
export function createJobError(error: DatabaseError) {
	if (error.code === '42501') return notFound(JOB_NOT_FOUND);
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'That job was already started with different details.',
				reason: 'already_started'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'That job cannot be created as entered.' });
	return databaseError();
}

// `update_job_details` and the four Part 11a pricing commands (`replace_job_line_items`, `set_job_billing`,
// `set_job_discount`, `set_job_tax`) refuse in the same shapes. A member without the permission, or a job in
// another organization, comes back as insufficient_privilege — a stranger cannot tell which. A revision that
// no longer matches is a stale write: the browser is told to reload rather than overwrite someone else's
// change. The table's own checks — a title's length, a line's shape, the 100-line cap (54000) — surface as a
// form error carrying the sentence the database already wrote, rather than a raw constraint violation.
export function updateJobError(error: DatabaseError) {
	if (error.code === '42501') return notFound(JOB_NOT_FOUND);
	if (error.code === 'P0404') return notFound('That job could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'Someone else changed this job. Reload to see the latest.',
				reason: 'stale'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514' || error.code === '23503' || error.code === '54000')
		return validationError({ form: error.message ?? 'Those details cannot be saved as entered.' });
	return databaseError();
}

// The four scheduling commands (`add_job_visits`, `update_job_visit`, `move_job_visits`, `delete_job_visit`)
// refuse in the same shapes. A member without jobs.schedule, or a job or visit in another organization, comes
// back as insufficient_privilege — a stranger cannot tell which. A missing job or visit is a not-found. A
// stale revision, or an idempotency key reused with different details, is a conflict the browser resolves by
// reloading. A completed visit or a closed job (P0410) is a rule, not a reload: the action simply cannot
// apply. The table's own shape checks and its foreign keys surface as a form error rather than a raw
// constraint violation.
export function scheduleVisitError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That job or visit could not be found.');
	if (error.code === 'P0404') return notFound(error.message ?? 'That could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'Someone else changed this. Reload to see the latest.',
				reason: 'stale'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === 'P0410')
		return json(
			{
				error: error.message ?? 'That visit can no longer be changed.',
				reason: 'locked'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'That visit cannot be saved as entered.' });
	return databaseError();
}
