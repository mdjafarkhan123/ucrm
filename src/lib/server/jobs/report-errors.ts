import { databaseError, notFound, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// `job_report_state`, `save_job_report`, `issue_job_report_access_link` and `revoke_job_report_access_link`
// all refuse in the same shapes, and each raise already carries the sentence a person should read.
//
//   insufficient_privilege — no jobs.edit, or a job in another organization. Both come back as not-found so
//                            a stranger learns nothing from the difference.
//   P0404 — the job, signature, photo or checklist answer named is not there.
//   P0400 / 23514 / 23503 — the shape of what was sent cannot be stored, including the two content gates
//                           (no content to share, no client email) `issue_job_report_access_link` checks.
export function jobReportWriteError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That job could not be found.');
	if (error.code === 'P0404') return notFound(error.message ?? 'That could not be found.');
	if (error.code === 'P0400' || error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'That cannot be saved as entered.' });
	return databaseError();
}

// The editor read refuses in the same two shapes as every other job read: no access, or nothing there.
export function jobReportReadError(error: DatabaseError) {
	if (error.code === '42501' || error.code === 'P0404')
		return notFound(error.message ?? 'That could not be found.');
	return databaseError();
}
