import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { markConversationReadSchema } from '$lib/server/validation/communications.schema';

// Per-user "last seen" position for one client's conversation (docs/unified-inbox-behavior-contract.md's
// "opening alone does not clear it; ... explicitly marking read ... may clear unread"). Selecting any
// inbound message from a client marks everything from that client read as of now -- there is no per-message
// read state, only a per-conversation high-water mark.
export const POST: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	let access;
	try {
		access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
	} catch (error) {
		console.error('Could not resolve conversation access.', error);
		return databaseError();
	}
	const canView =
		hasPermission(access, 'conversations.view_team') ||
		hasPermission(access, 'conversations.view_assigned');
	if (!canView) {
		return json(
			{ error: 'You do not have access to conversations.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = markConversationReadSchema.safeParse(body);
	if (!parsed.success) return validationError({ client_id: 'Choose a valid conversation.' });

	const organizationId = auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_mark_read:${organizationId}:${auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 120
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const lastReadAt = new Date().toISOString();
		const { error } = await ownerClient.from('communication_conversation_read_marks').upsert(
			{
				organization_id: organizationId,
				user_id: auth.user.id,
				client_id: parsed.data.client_id,
				last_read_at: lastReadAt
			},
			{ onConflict: 'organization_id,user_id,client_id' }
		);
		if (error) {
			console.error('Could not mark the conversation read.', error);
			return databaseError();
		}
		return json({ last_read_at: lastReadAt }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not mark the conversation read.', error);
		return databaseError();
	}
};
