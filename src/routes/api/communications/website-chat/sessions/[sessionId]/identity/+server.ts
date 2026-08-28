import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	websiteChatResolveIdentitySchema
} from '$lib/server/validation/communications.schema';
import {
	UUID_PATTERN,
	websiteChatCommandError
} from '$lib/server/communications/website-chat-staff';

// Says which Client a conflicting-identity session actually belongs to.
//
// A session lands at match_status = 'needs_review' when the visitor's phone matched one Client and
// their email matched a different one; UCRM never guesses, a person chooses. Choosing is the same
// administrative act as linking a guarded inbound sender, so it carries the same pair of permissions:
// conversations.manage_assignment to act on the conversation, customers.view to read the contact it is
// being attached to. Both are re-checked inside the command; customers.view is checked here too so the
// refusal reads as a permission problem rather than a 422.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_assignment');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

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
	const parsed = websiteChatResolveIdentitySchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the chosen client.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `website_chat_staff_identity:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 30
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const { data, error } = await ownerClient.rpc('resolve_website_chat_session_identity', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_session_id: sessionId,
			target_client_id: parsed.data.client_id
		});
		if (error) {
			const refusal = websiteChatCommandError(error);
			if (refusal) return refusal;
			console.error('Could not resolve a Website Chat identity.', error);
			return databaseError();
		}

		return json(data, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not resolve a Website Chat identity.', error);
		return databaseError();
	}
};
