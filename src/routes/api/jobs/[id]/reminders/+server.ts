import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { addJobInvoiceReminderSchema } from '$lib/server/validation/jobs.schema';
import { reminderError } from '$lib/server/jobs/errors';

// Add a custom-date invoice reminder to a job — an internal to-do for our own team, never a message to the
// client. The month-end reminder seeds itself from the billing choice through a trigger; this route is only
// the manual "remind us on this date" a person types. `add_job_invoice_reminder` checks jobs.edit itself and
// treats re-adding the same open date as a no-op that returns the reminder already there, so a double click
// cannot pile up duplicates.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = addJobInvoiceReminderSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('add_job_invoice_reminder', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		new_due_on: parsed.data.due_on,
		new_note: parsed.data.note
	});

	if (error) return reminderError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
