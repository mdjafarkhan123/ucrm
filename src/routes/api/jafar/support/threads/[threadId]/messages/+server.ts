import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { supportMessageSchema } from '$lib/server/validation/support.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// Uplift replies. The contractor sees "Uplift Support" with the responder name saved in Support settings;
// the owner login that sent it is kept on the message for Uplift's own record.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const threadId = z.string().uuid().safeParse(event.params.threadId);
	if (!threadId.success)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = supportMessageSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review your reply.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('reply_to_support_thread', {
		target_thread_id: threadId.data,
		actor_email: session.email,
		message_body: parsed.data.body,
		message_client_id: parsed.data.client_message_id
	});
	if (error) {
		// The function's own sentences are written for Jafar: the missing responder name, the length.
		if (error.code === '23514') return json({ error: error.message }, { status: 422 });
		if (error.code === 'P0002')
			return json({ error: 'That conversation no longer exists.' }, { status: 404 });
		console.error('Could not send a support reply.', error);
		return json({ error: 'Your reply could not be sent.' }, { status: 500 });
	}

	return json(data, { status: 201 });
};
