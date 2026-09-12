import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// The form commands refuse in three shapes, and each raise already carries the sentence a person should
// read, so this maps the code and passes the words through:
//
//   insufficient_privilege (42501) — no permission, or a form in another organization. Returned as
//                                    not-found so a stranger learns nothing from the difference.
//   P0409 — a stale edit: someone changed this form or draft since it was loaded. The screen reloads.
//   23514 / 23503 — the shape or state of what was sent cannot be stored (bad outcome, archived form,
//                   no draft to edit, etc.). Shown against the form.
export function formWriteError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That form could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'Someone else changed this form. Reload and try again.',
				reason: 'stale_revision'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'That cannot be saved as entered.' });
	return databaseError();
}

// Reads refuse in one shape only — no access — which is a not-found to the browser.
export function formReadError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That form could not be found.');
	return databaseError();
}
