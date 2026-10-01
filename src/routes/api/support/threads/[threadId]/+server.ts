import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { supportChangeFailure } from '$lib/server/support/people';
import { readTopicChange } from '$lib/server/support/topic';

// Changes a chat's topic. Only the person who started it, or an owner or admin, may.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const change = await readTopicChange(event.params, event.request);
	if ('response' in change) return change.response;

	const { data, error } = await event.locals.supabase.rpc('set_support_thread_topic', {
		target_thread_id: change.threadId,
		new_topic: change.topic
	});
	if (error) return supportChangeFailure(error);
	return json({ changed: data }, { headers: NO_STORE_HEADERS });
};
