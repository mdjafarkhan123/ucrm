import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Client onboarding C2: Jafar pauses or resumes one client's setup reminder emails (plan §5, "a human
// deferral"). Resuming starts a fresh quiet spell, so no reminder goes out the moment they are back on. The
// database records each change in Jafar's history.

const bodySchema = z.object({ paused: z.boolean() }).strict();

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('This business has no setup reminders.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = bodySchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'Say whether to pause the reminders.' });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_set_setup_reminders_paused', {
		target_organization_id: organizationId.data,
		actor_email: session.email,
		pause: parsed.data.paused
	});
	if (error) {
		if (error.code === 'P0002') return notFound('This business has no setup reminders.');
		console.error('Could not change setup reminders.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
