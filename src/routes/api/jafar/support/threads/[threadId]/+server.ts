import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSupportInboxThread } from '$lib/server/support/inbox';
import { readSupportMessages } from '$lib/server/support/read';
import { supportChangeFailure } from '$lib/server/support/people';
import { readTopicChange } from '$lib/server/support/topic';
import { supportThreadQuerySchema } from '$lib/server/validation/support.schema';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const threadId = z.string().uuid().safeParse(event.params.threadId);
	const parsed = supportThreadQuerySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined
	});
	if (!threadId.success || !parsed.success)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

	try {
		const client = getOwnerSupabaseClient();
		const [thread, page] = await Promise.all([
			readSupportInboxThread(client, threadId.data),
			readSupportMessages(client, threadId.data, parsed.data.limit)
		]);
		if (!thread) return json({ error: 'That conversation could not be found.' }, { status: 404 });
		if (!page) throw new Error('The messages could not be read.');

		return json({ thread, ...page });
	} catch (error) {
		console.error('Could not load a support conversation.', error);
		return json({ error: 'This conversation could not be loaded.' }, { status: 500 });
	}
};

// Uplift changes a chat's topic; the grey line reads "Uplift Support changed the topic to …".
export const PATCH: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const change = await readTopicChange(event.params, event.request);
	if ('response' in change) return change.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('set_support_thread_topic_by_uplift', {
		target_thread_id: change.threadId,
		new_topic: change.topic
	});
	if (error) return supportChangeFailure(error);
	return json({ changed: data });
};
