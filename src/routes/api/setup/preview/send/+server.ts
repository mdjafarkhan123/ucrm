import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';
import { setupPreviewVersionSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E3 (plan §6): sends the team's notes on a preview to Uplift, once. A second press or a second
// device gets 'already_sent' and changes nothing.
export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
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
	const parsed = setupPreviewVersionSchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'Choose a preview.' });

	const { data, error } = await event.locals.supabase.rpc('client_send_setup_preview_notes', {
		target_organization_id: organizationId,
		target_version: parsed.data.version
	});
	if (error) return setupWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
