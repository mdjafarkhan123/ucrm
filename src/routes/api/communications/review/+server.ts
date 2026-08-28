import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { resolveInboundReviewSchema } from '$lib/server/validation/communications.schema';

// Resolves a guarded ("Needs review") conversation: link every pending message from that sender address
// to a client, or dismiss them. A guarded conversation has no client_id yet, so it is addressed here by
// the sender's email -- resolve_inbound_message_review re-checks permission, org state, and the client
// before writing anything, so this route only forwards the choice.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_assignment');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = resolveInboundReviewSchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'Choose a valid conversation.' });

	const input = parsed.data;
	if (input.resolution === 'link' && !input.client_id) {
		return validationError({ client_id: 'Choose a client to link this conversation to.' });
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_review_resolve:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 60
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const { data, error } = await ownerClient.rpc('resolve_inbound_message_review', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_sender_email: input.sender_email,
			target_resolution: input.resolution,
			// The command defaults this to null; the generated RPC type accepts only `string | undefined`.
			target_client_id: input.resolution === 'link' ? (input.client_id ?? undefined) : undefined
		});
		if (error) {
			const dbError = error as { code?: string; message?: string };
			// Every one of these is a message the operator can act on: missing permission, an unavailable
			// client, a conversation someone else already resolved, or a rejected resolution.
			if (['42501', '23503', '55000', '22023'].includes(dbError.code ?? '')) {
				return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
			}
			console.error('Could not resolve the guarded conversation.', error);
			return databaseError();
		}

		return json(
			{ resolution: input.resolution, resolved_count: data, client_id: input.client_id ?? null },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not resolve the guarded conversation.', error);
		return databaseError();
	}
};
