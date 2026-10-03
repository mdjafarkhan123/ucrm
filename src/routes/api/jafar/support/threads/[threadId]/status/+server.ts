import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { supportChangeFailure } from '$lib/server/support/people';
import { supportStatusSchema } from '$lib/server/validation/support.schema';

// Uplift marks a chat Solved or reopens it (D5a; only the support side closes a chat, as in Intercom and
// Zendesk). The grey line reads "Uplift Support marked this chat as solved." A member writing reopens it
// without this route.
export const PATCH: RequestHandler = async (event) => {
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

	const parsed = supportStatusSchema.safeParse(body);
	if (!parsed.success) return json({ error: 'Choose open or solved.' }, { status: 422 });

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'set_support_thread_status_by_uplift',
		{
			target_thread_id: threadId.data,
			new_status: parsed.data.status
		}
	);
	if (error) return supportChangeFailure(error);
	return json({ changed: data });
};
