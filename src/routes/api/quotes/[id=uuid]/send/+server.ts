import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { quoteWriteError } from '$lib/server/quotes/errors';
import { sendDraftQuoteByEmail } from '$lib/server/quotes/send';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { sendDraftQuoteSchema } from '$lib/server/validation/quotes.schema';

function sendNotAllowed(message: string) {
	return json(
		{ error: message, reason: 'permission_denied' },
		{ status: 403, headers: NO_STORE_HEADERS }
	);
}

// The Quote page's Draft -> Awaiting response, the same two ways the board's send window offers: UCRM
// emails the quote, or a person records that they already sent it and how. Nothing is claimed about the
// customer until one of them really happens, and a refusal leaves the quote a Draft.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.send');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = sendDraftQuoteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const { send, idempotency_key: idempotencyKey } = parsed.data;

	if (send.method === 'email') {
		// The email also opens a customer conversation, so it needs that permission as well.
		if (!hasPermission(check.access, 'conversations.send')) {
			return sendNotAllowed('You do not have permission to email customers.');
		}
		// The email path keeps its own per-person limit inside the send.
		const refusal = await sendDraftQuoteByEmail({
			organizationId: check.auth.organization.id,
			actorUserId: check.auth.user.id,
			quoteId: event.params.id,
			expectedRevision: send.expected_revision,
			idempotencyKey
		});
		if (refusal) return refusal;
	} else {
		const limited = await enforceOrganizationWriteRateLimit(
			event.locals.supabase,
			check.auth.organization.id,
			'quotes'
		);
		if (limited) return limited;

		const { error } = await event.locals.supabase.rpc('mark_quote_sent_externally', {
			target_quote_id: event.params.id,
			expected_revision: send.expected_revision,
			send_channel: send.channel,
			send_note: send.note ?? undefined
		});
		if (error) return quoteWriteError(error);
	}

	return json({ id: event.params.id, method: send.method }, { headers: NO_STORE_HEADERS });
};
