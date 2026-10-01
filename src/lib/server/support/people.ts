import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { PostgrestError } from '@supabase/supabase-js';
import { supportPersonSchema } from '$lib/server/validation/support.schema';

// Who is in a support conversation (D3), shared by the member routes and the /jafar routes. The database
// functions decide who may change the list and write the grey "added / removed" line; these helpers only
// read the request and turn the database's refusals into answers.

const NOT_FOUND = { error: 'That conversation could not be found.' };

/** The conversation id from the path, and the teammate from the body (adding) or the path (removing). */
export async function readPeopleChange(
	params: { threadId?: string; userId?: string },
	request: Request,
	adding: boolean
): Promise<{ threadId: string; userId: string } | { response: Response }> {
	const threadId = z.string().uuid().safeParse(params.threadId);
	if (!threadId.success) return { response: json(NOT_FOUND, { status: 404 }) };

	if (!adding) {
		const userId = z.string().uuid().safeParse(params.userId);
		if (!userId.success)
			return { response: json({ error: 'Choose a teammate.' }, { status: 422 }) };
		return { threadId: threadId.data, userId: userId.data };
	}

	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return { response: json({ error: 'Request body must be valid JSON.' }, { status: 400 }) };
	}
	const parsed = supportPersonSchema.safeParse(body);
	if (!parsed.success)
		return {
			response: json(
				{ error: 'Choose a teammate.', field_errors: { user_id: 'Choose a teammate.' } },
				{ status: 422 }
			)
		};
	return { threadId: threadId.data, userId: parsed.data.user_id };
}

/** The database's own sentences are written for the person: "Only an active member of this team…". */
export function supportChangeFailure(error: PostgrestError): Response {
	if (error.code === '42501')
		return json({ error: error.message, reason: 'permission_denied' }, { status: 403 });
	if (error.code === '23514') return json({ error: error.message }, { status: 422 });
	if (error.code === 'P0002') return json(NOT_FOUND, { status: 404 });
	console.error('Could not change a support conversation.', error);
	return json({ error: 'That change could not be saved.' }, { status: 500 });
}

export function peopleReadFailure(error: PostgrestError): Response {
	if (error.code === 'P0002') return json(NOT_FOUND, { status: 404 });
	console.error('Could not read who is in a support conversation.', error);
	return json({ error: 'The people in this conversation could not be loaded.' }, { status: 500 });
}
