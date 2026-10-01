import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import {
	supportChangeFailure,
	peopleReadFailure,
	readPeopleChange
} from '$lib/server/support/people';

// Who is in a conversation, and who could be added. Any member who can see the conversation may look.
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const threadId = z.string().uuid().safeParse(event.params.threadId);
	if (!threadId.success)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

	const { data, error } = await event.locals.supabase.rpc('support_thread_people', {
		target_thread_id: threadId.data
	});
	if (error) return peopleReadFailure(error);
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Adds a teammate. Only the person who started the conversation, or an owner or admin, may.
export const POST: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const change = await readPeopleChange(event.params, event.request, true);
	if ('response' in change) return change.response;

	const { data, error } = await event.locals.supabase.rpc('set_support_thread_participant', {
		target_thread_id: change.threadId,
		target_user_id: change.userId,
		adding: true
	});
	if (error) return supportChangeFailure(error);
	return json({ changed: data }, { headers: NO_STORE_HEADERS });
};
