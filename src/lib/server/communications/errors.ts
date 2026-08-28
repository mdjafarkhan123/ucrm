import { json } from '@sveltejs/kit';
import { databaseError, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// Snippets are written straight through PostgREST behind a plain RLS policy, so the route's own
// `requireOrganizationPermission` gate already refuses before any query runs -- 42501 here only ever means
// the gate and RLS disagreed, still worth a clear 403 rather than a generic save failure.
export function snippetWriteError(error: DatabaseError) {
	if (error.code === '42501') {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}
	if (error.code === '23514') return validationError({ form: 'Check the title and body.' });
	return databaseError();
}

// Email templates are RLS-gated to owners/admins, one step stricter than Snippets -- the route's own
// `requireOrganizationAdmin` gate already refuses before any query runs, so 42501 here only ever means the
// gate and RLS disagreed. 23503 covers a copy racing a platform template's deletion between browse and copy.
export function emailTemplateWriteError(error: DatabaseError) {
	if (error.code === '42501') {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}
	if (error.code === '23503') {
		return json({ error: 'That platform template is no longer available.' }, { status: 409 });
	}
	if (error.code === '23514')
		return validationError({ form: 'Check the name, subject, and body.' });
	return databaseError();
}
