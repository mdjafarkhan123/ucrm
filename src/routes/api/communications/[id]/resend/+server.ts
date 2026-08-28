import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { createQuoteEmailAccessLink } from '$lib/server/communications/quote-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { resendCommunicationEmailSchema } from '$lib/server/validation/communications.schema';

type DatabaseError = { code?: string; message?: string };

function resendError(error: DatabaseError) {
	if (error.code === '42501') {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}
	if (error.code === 'P0002') return notFound('That message could not be found.');
	if (error.code === '55000') {
		return json(
			{
				error: error.message ?? 'This message cannot be resent right now.',
				reason: 'not_resendable'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	}
	return databaseError();
}

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = resendCommunicationEmailSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: 'Start a new resend attempt and try again.' });

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_resend:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		// Only used to decide whether to mint a fresh quote link before calling the command. The command
		// re-reads and re-authorizes the original message itself; this lookup is never a security decision.
		const { data: original } = await ownerClient
			.from('communication_delivery_intents')
			.select('quote_id')
			.eq('organization_id', organizationId)
			.eq('id', event.params.id)
			.maybeSingle();

		const link = original?.quote_id ? createQuoteEmailAccessLink() : null;
		const { data, error } = await ownerClient.rpc('resend_communication_email', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_original_intent_id: event.params.id,
			target_logical_send_key: parsed.data.idempotency_key,
			target_quote_url: link?.url ?? undefined,
			target_quote_token_hash: link?.tokenHash ?? undefined
		});
		if (error) return resendError(error);
		return json(
			{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not resend the communication email.', error);
		return json(
			{ error: 'The message could not be resent.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
