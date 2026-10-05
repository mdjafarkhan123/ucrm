import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readOwnerPreviews } from '$lib/server/setup/preview';
import { readSetupServiceKeys } from '$lib/server/setup/catalogue';
import { setupPreviewDraftSchema } from '$lib/server/validation/setup.schema';
import { resolvePreviewScreenshots } from '$lib/server/setup/preview-screenshots';
import type { Json } from '$lib/database.types';

// Client onboarding E3 (plan §6): Jafar's preview for one client — whether one can be written yet, his draft, and
// every released version with the client's notes (GET); saving the draft whole (POST); throwing it away (DELETE).

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	const client = getOwnerSupabaseClient();
	try {
		const [previews, serviceKeys] = await Promise.all([
			readOwnerPreviews(client, organizationId.data),
			readSetupServiceKeys(client, organizationId.data)
		]);
		if (!serviceKeys) throw new Error('The package could not be read.');
		return json({ ...previews, service_keys: [...serviceKeys] }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read the preview.', error);
		return databaseError();
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupPreviewDraftSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Check the cards.' });

	// Each card's screenshots, measured in storage under this client's preview folder.
	const cards = [];
	for (const card of parsed.data.cards) {
		const screenshots = await resolvePreviewScreenshots(organizationId.data, card.screenshots);
		if ('response' in screenshots) return screenshots.response;
		cards.push({ ...card, screenshots: screenshots.screenshots });
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_save_setup_preview', {
		target_organization_id: organizationId.data,
		new_cards: cards as unknown as Json,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not save the preview.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_discard_setup_preview_draft', {
		target_organization_id: organizationId.data,
		actor_email: session.email
	});
	if (error) {
		console.error('Could not discard the preview draft.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
