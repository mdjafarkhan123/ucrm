import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { peopleChangeFailure, readPeopleChange } from '$lib/server/support/people';

// Removes a teammate who was added. The person who started the conversation always stays in it.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const change = await readPeopleChange(event.params, event.request, false);
	if ('response' in change) return change.response;

	const { data, error } = await event.locals.supabase.rpc('set_support_thread_participant', {
		target_thread_id: change.threadId,
		target_user_id: change.userId,
		adding: false
	});
	if (error) return peopleChangeFailure(error);
	return json({ changed: data }, { headers: NO_STORE_HEADERS });
};
