import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { supportUpliftReadSchema } from '$lib/server/validation/support.schema';

// Uplift's screen showed this conversation up to `read_through`, so it stops counting as unread.
export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const threadId = z.string().uuid().safeParse(event.params.threadId);
	if (!threadId.success)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = supportUpliftReadSchema.safeParse(body);
	if (!parsed.success) return json({ error: 'The read time is invalid.' }, { status: 422 });

	const { error } = await getOwnerSupabaseClient().rpc('mark_support_thread_read_by_uplift', {
		target_thread_id: threadId.data,
		read_through: parsed.data.read_through
	});
	if (error) {
		console.error('Could not mark a support conversation as read.', error);
		return json({ error: 'The conversation could not be marked as read.' }, { status: 500 });
	}

	return new Response(null, { status: 204 });
};
