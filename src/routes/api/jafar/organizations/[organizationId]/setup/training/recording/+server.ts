import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { setupTrainingRecordingSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E6 (plan §6): Jafar adds the private training recording link after training, only while the
// client consents, or removes it (`recording_url` null) at any time. It shows only on the handover pack, never in
// an email.

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
	const parsed = setupTrainingRecordingSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Check the link.' });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_set_setup_training_recording', {
		target_organization_id: organizationId.data,
		// Null removes the link. It must be sent, not left out: the function has no default for it.
		new_recording_url: parsed.data.recording_url as string,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not change the training recording.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
