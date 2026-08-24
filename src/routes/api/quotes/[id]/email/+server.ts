import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { createQuoteEmailAccessLink } from '$lib/server/communications/quote-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { quoteWriteError } from '$lib/server/quotes/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { quoteEmailSchema } from '$lib/server/validation/quotes.schema';

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.send');
	if ('response' in check) return check.response;
	// A published quote is a commercial document, but email delivery also creates a customer
	// conversation. Keep the route aligned with the command so a direct request cannot reach a
	// service-only RPC that will necessarily refuse it.
	if (!hasPermission(check.access, 'conversations.send')) {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = quoteEmailSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_quote_email:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);
		const link = createQuoteEmailAccessLink();
		const { data, error } = await ownerClient.rpc('enqueue_quote_communication_email', {
			target_organization_id: check.auth.organization.id,
			target_actor_user_id: check.auth.user.id,
			target_quote_id: event.params.id,
			target_logical_send_key: parsed.data.idempotency_key,
			target_quote_url: link.url,
			target_quote_token_hash: link.tokenHash
		});
		if (error) return quoteWriteError(error);
		return json(
			{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not queue quote email.', error);
		return json(
			{ error: 'The quote email could not be queued.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
