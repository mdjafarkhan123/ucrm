import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	websiteChatStaffMessageSchema
} from '$lib/server/validation/communications.schema';
import {
	UUID_PATTERN,
	websiteChatCommandError
} from '$lib/server/communications/website-chat-staff';

// A staff reply into a live Website Chat session.
//
// Addressed by session id, not client id: a conflicting-identity session has no client yet and is still
// a real, replyable conversation (Intercom and Drift both work this way). post_website_chat_staff_message
// re-checks conversations.send against the acting member, refuses a closed session, and replays a
// retried send, so this route only forwards the choice.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const sessionId = event.params.sessionId;
	if (!sessionId || !UUID_PATTERN.test(sessionId)) {
		return validationError({ form: 'Choose a valid conversation.' });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = websiteChatStaffMessageSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the reply.', field_errors: communicationFieldErrors(parsed.error) },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		// Chat is typed in short bursts, so this sits well above the email reply limit and still stops a
		// runaway client from flooding a visitor's widget.
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `website_chat_staff_send:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 60
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const { data, error } = await ownerClient.rpc('post_website_chat_staff_message', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_session_id: sessionId,
			message_body: parsed.data.body,
			new_idempotency_key: parsed.data.idempotency_key
		});
		if (error) {
			const refusal = websiteChatCommandError(error);
			if (refusal) return refusal;
			console.error('Could not send a Website Chat reply.', error);
			return databaseError();
		}

		return json(data, { status: 201, headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not send a Website Chat reply.', error);
		return databaseError();
	}
};
