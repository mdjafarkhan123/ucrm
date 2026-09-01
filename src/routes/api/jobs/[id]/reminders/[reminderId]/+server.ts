import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { reminderError } from '$lib/server/jobs/errors';

// Dismiss a reminder: mark it handled without deleting it, so the row stays as proof the job was billed
// outside the system. A month-end reminder rolls forward to next month's on dismissal — the database does
// that inside the command. Needs jobs.edit, which `dismiss_job_invoice_reminder` checks itself.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('dismiss_job_invoice_reminder', {
		target_organization_id: check.auth.organization.id,
		target_reminder_id: event.params.reminderId
	});

	if (error) return reminderError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// Delete a reminder that should never have existed — a custom date typed wrong. Only manual custom-date
// reminders can be deleted; the auto month-end one is managed by its policy and must be dismissed instead,
// which `delete_job_invoice_reminder` enforces (it raises on any other kind). Needs jobs.edit.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('delete_job_invoice_reminder', {
		target_organization_id: check.auth.organization.id,
		target_reminder_id: event.params.reminderId
	});

	if (error) return reminderError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
