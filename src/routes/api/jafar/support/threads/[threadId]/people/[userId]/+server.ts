import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { peopleChangeFailure, readPeopleChange } from '$lib/server/support/people';

export const DELETE: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const change = await readPeopleChange(event.params, event.request, false);
	if ('response' in change) return change.response;

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'set_support_thread_participant_by_uplift',
		{ target_thread_id: change.threadId, target_user_id: change.userId, adding: false }
	);
	if (error) return peopleChangeFailure(error);
	return json({ changed: data });
};
