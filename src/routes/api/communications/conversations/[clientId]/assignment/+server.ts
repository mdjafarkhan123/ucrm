import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { assignConversationSchema } from '$lib/server/validation/communications.schema';

type DatabaseError = { code?: string; message?: string };

// Sets or clears the conversation's owner. A guarded/unresolved-sender conversation has no client_id and
// so can never be assigned -- Part 5C's forward/attach flow is the only path that gives one an identity.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_assignment');
	if ('response' in check) return check.response;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = assignConversationSchema.safeParse(body);
	if (!parsed.success) return validationError({ assigned_to: 'Choose a valid team member.' });

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_assign:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 60
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		if (parsed.data.assigned_to === null) {
			const { error } = await ownerClient
				.from('communication_conversation_assignments')
				.delete()
				.eq('organization_id', organizationId)
				.eq('client_id', clientId);
			if (error) return databaseError();
			return json({ assigned_to: null }, { headers: NO_STORE_HEADERS });
		}

		const { error } = await ownerClient.from('communication_conversation_assignments').upsert(
			{
				organization_id: organizationId,
				client_id: clientId,
				assigned_to: parsed.data.assigned_to,
				assigned_by: check.auth.user.id,
				assigned_at: new Date().toISOString()
			},
			{ onConflict: 'organization_id,client_id' }
		);
		if (error) {
			const dbError = error as DatabaseError;
			// Raised by communication_conversation_assignee_eligible() -- the chosen member cannot see
			// conversations at all (no conversations.view_team or view_assigned), so they cannot be assigned.
			if (dbError.code === '23514') {
				return validationError({ assigned_to: 'That person cannot be assigned conversations.' });
			}
			// The client_id or organization foreign key rejected the row -- not a real conversation.
			if (dbError.code === '23503')
				return validationError({ form: 'Choose a valid conversation.' });
			console.error('Could not assign the conversation.', error);
			return databaseError();
		}
		return json({ assigned_to: parsed.data.assigned_to }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not assign the conversation.', error);
		return databaseError();
	}
};
