import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { recordSetupHelpAnswer } from '$lib/server/setup/help';
import { setupHelpAnswerSchema } from '$lib/server/validation/setup.schema';

// Client onboarding C3c: Jafar records the answer Uplift found for a question the client asked help with, on
// their newest send (plan §4, §10 journey 4). The help request closes only with this answer; the client's own
// "I need Uplift's help" is kept. An answer on an earlier send is refused with 409.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That setup send does not exist.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupHelpAnswerSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues) {
			const field = String(issue.path[0] ?? 'form');
			fieldErrors[field] ??= issue.message;
		}
		return validationError(fieldErrors);
	}

	try {
		const result = await recordSetupHelpAnswer(
			getOwnerSupabaseClient(),
			organizationId.data,
			session.email,
			parsed.data
		);
		if (result.status === 'not_found') return notFound(result.message);
		if (result.status === 'invalid') return validationError({ [result.field]: result.message });
		if (result.status === 'stale')
			return json(
				{
					error:
						'The client has sent their setup again since you opened it. Look at the newest send first.',
					latest_number: result.latest_number
				},
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		return json(result, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not record Uplift’s answer to a help request.', error);
		return databaseError();
	}
};
