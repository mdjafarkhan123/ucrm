import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// The checklist commands refuse in five shapes, and each raise already carries the sentence a person should
// read, so this maps the code and passes the words through.
//
//   insufficient_privilege — no permission, or a job in another organization. Both come back as not-found
//                            so a stranger learns nothing from the difference.
//   P0404 — the checklist, question or visit is not there.
//   P0409 — the same checklist is already on this job.
//   P0410 — a rule, not a reload: a closed job, or a checklist added after this visit was completed.
//   P0400 / 23514 / 23503 — the shape of what was sent cannot be stored.
export function checklistWriteError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That checklist could not be found.');
	if (error.code === 'P0404') return notFound(error.message ?? 'That could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'That checklist is already on this job.',
				reason: 'already_attached'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === 'P0410')
		return json(
			{ error: error.message ?? 'That cannot be changed now.', reason: 'not_allowed_now' },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === 'P0400' || error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'That cannot be saved as entered.' });
	return databaseError();
}

// The reads refuse in two shapes only: no access, or nothing there. Both are a not-found to the browser.
export function checklistReadError(error: DatabaseError) {
	if (error.code === '42501' || error.code === 'P0404')
		return notFound(error.message ?? 'That could not be found.');
	return databaseError();
}
