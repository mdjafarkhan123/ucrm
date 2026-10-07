import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { leadDetailsEditSchema } from '$lib/server/validation/lead.schema';

// Jafar business management B2b: editing a Lead's business, contact details and About from its page. The
// database saves every change and its one history line together.

const LEAD_NOT_FOUND = 'This Lead no longer exists.';

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadDetailsEditSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return validationError(fieldErrors);
	}

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_update_details', {
			actor_email: session.email,
			target_id: event.params.id,
			fields: parsed.data.fields,
			contact_methods: parsed.data.contact_methods
		});
		if (error) {
			// The database's own refusals (e.g. "A Lead can have at most ten contact details.") are in plain words.
			if (error.code === '22023') return validationError({ form: error.message }, 409);
			throw error;
		}
		if (data === 'lead_not_found') return notFound(LEAD_NOT_FOUND);
		return json({ result: data });
	} catch (error) {
		console.error('Could not save the Lead details.', error);
		return databaseError();
	}
};
