import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { setupPreviewSortSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E3 (plan §6): Jafar labels one sent note — Correction, Our mistake, or New request. The client
// sees the label beside their note.
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
	const parsed = setupPreviewSortSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Choose a label.' });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_sort_setup_preview_note', {
		target_organization_id: organizationId.data,
		target_version: parsed.data.version,
		target_card_id: parsed.data.card_id,
		new_kind: parsed.data.kind,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not sort a preview note.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
