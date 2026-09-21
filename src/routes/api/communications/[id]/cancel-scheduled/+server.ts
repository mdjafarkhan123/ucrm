import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

type DatabaseError = { code?: string; message?: string };

function cancelError(error: DatabaseError) {
	if (error.code === '42501') {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}
	if (error.code === 'P0002') return notFound('That scheduled message could not be found.');
	if (error.code === '55000') {
		return json(
			{
				error:
					error.message ??
					'This message has already started sending and can no longer be cancelled.',
				reason: 'not_cancellable'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	}
	return databaseError();
}

// Cancels a still-scheduled ("Send Later") email reply before the worker claims it -- see
// cancel_communication_conversation_reply. Nothing to validate from the request body: the target is the
// intent id in the URL, and the command itself re-checks it is still cancellable.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_cancel_scheduled:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const { data, error } = await ownerClient.rpc('cancel_communication_conversation_reply', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_delivery_intent_id: event.params.id
		});
		if (error) return cancelError(error);
		return json(
			{ intent: { id: data.id, status: data.status } },
			{ status: 200, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not cancel the scheduled message.', error);
		return json(
			{ error: 'The scheduled message could not be cancelled.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
