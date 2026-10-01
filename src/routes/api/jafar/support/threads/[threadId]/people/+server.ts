import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	peopleChangeFailure,
	peopleReadFailure,
	readPeopleChange
} from '$lib/server/support/people';

// Uplift sees and changes who is in any conversation. The grey line reads "Uplift Support added …".
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const threadId = z.string().uuid().safeParse(event.params.threadId);
	if (!threadId.success)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

	const { data, error } = await getOwnerSupabaseClient().rpc('support_thread_people_for_uplift', {
		target_thread_id: threadId.data
	});
	if (error) return peopleReadFailure(error);
	if (!data) return json({ error: 'That conversation could not be found.' }, { status: 404 });
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const change = await readPeopleChange(event.params, event.request, true);
	if ('response' in change) return change.response;

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'set_support_thread_participant_by_uplift',
		{ target_thread_id: change.threadId, target_user_id: change.userId, adding: true }
	);
	if (error) return peopleChangeFailure(error);
	return json({ changed: data });
};
