import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';
import { resolvePreviewScreenshots } from '$lib/server/setup/preview-screenshots';
import { setupPreviewNoteSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { Json } from '$lib/database.types';

// Client onboarding E3 (plan §6): saves the client's choice and note on one card as a draft, or clears it. The
// database refuses a choice the version does not offer, an old version, and anything after the notes were sent.
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
	const parsed = setupPreviewNoteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const keep = parsed.data.choice !== null && parsed.data.choice !== 'looks_right';
	const screenshots = await resolvePreviewScreenshots(
		organizationId,
		keep ? parsed.data.screenshots : []
	);
	if ('response' in screenshots) return screenshots.response;

	const { data, error } = await event.locals.supabase.rpc('client_save_setup_preview_note', {
		target_organization_id: organizationId,
		target_version: parsed.data.version,
		target_card_id: parsed.data.card_id,
		// The database reads null as "clear this card's choice".
		new_choice: parsed.data.choice as string,
		new_note: parsed.data.note as string,
		new_screenshots: screenshots.screenshots as unknown as Json
	});
	if (error) return setupWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
