import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireSetupReader, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';
import { setupReminderEmailsSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Turns the signed-in person's own setup reminder emails on or off (C6, plan §5 opt-out). It changes nothing
// for the other owners and administrators, so anyone who can see setup may choose for themselves.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setupReminderEmailsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_my_setup_reminder_emails', {
		target_organization_id: organizationId,
		emails_on: parsed.data.emails_on
	});
	if (error) return setupWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
