import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	UUID_PATTERN,
	websiteChatCommandError
} from '$lib/server/communications/website-chat-staff';

// Ends a Website Chat session from the staff side.
//
// The command does both halves in one transaction -- closed_at/closed_reason/closed_by AND the
// sender_type = 'system' part in the thread -- because that part is the only way the visitor's widget
// learns the conversation ended (WC4.4's inherited contract, following Intercom's `part_type: close`).
// There is no request body: who ended it comes from the session, not from the browser.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const sessionId = event.params.sessionId;
	if (!sessionId || !UUID_PATTERN.test(sessionId)) {
		return validationError({ form: 'Choose a valid conversation.' });
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `website_chat_staff_end:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 30
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const { data, error } = await ownerClient.rpc('end_website_chat_session', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_session_id: sessionId
		});
		if (error) {
			const refusal = websiteChatCommandError(error);
			if (refusal) return refusal;
			console.error('Could not end a Website Chat session.', error);
			return databaseError();
		}

		return json(data, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not end a Website Chat session.', error);
		return databaseError();
	}
};
