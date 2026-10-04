import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { sendSetupReturnEmails } from '$lib/server/setup/return-email';
import { recordSectionReview } from '$lib/server/setup/review';
import { setupSectionReviewSchema } from '$lib/server/validation/setup.schema';

// Client onboarding C3: Jafar accepts one section of a client's newest send, or sends it back with a note and
// the questions to change (plan §4). A decision on an earlier send is refused with 409, so Jafar never accepts
// answers he has not seen. A return emails the client's owners and administrators straight to the section (C3b);
// the decision stands even if that email cannot be queued, and the reply says so, so Jafar can press Send back
// again, which queues only what is missing.

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
	const parsed = setupSectionReviewSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues) {
			const field = String(issue.path[0] ?? 'form');
			fieldErrors[field] ??= issue.message;
		}
		return validationError(fieldErrors);
	}

	const client = getOwnerSupabaseClient();
	let result;
	try {
		result = await recordSectionReview(client, organizationId.data, session.email, parsed.data);
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
	} catch (error) {
		console.error('Could not record a setup review.', error);
		return databaseError();
	}

	let emailed = true;
	if (parsed.data.decision === 'returned')
		try {
			await sendSetupReturnEmails(client, {
				organizationId: organizationId.data,
				sectionKey: parsed.data.section_key,
				origin: env.APP_URL?.trim() || event.url.origin
			});
		} catch (error) {
			console.error('Could not queue the email about a returned setup section.', error);
			emailed = false;
		}
	return json({ ...result, emailed }, { headers: NO_STORE_HEADERS });
};
