import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { createQuoteEmailAccessLink } from '$lib/server/communications/quote-email';
import { emailSendPrerequisiteResponse } from '$lib/server/communications/email-send-errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { quoteWriteError } from '$lib/server/quotes/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

// Sending a Draft quote by email: the draft is frozen and the customer's email is queued by one database
// command, so a send that cannot be queued leaves the quote a Draft. The customer link is made here, on
// the server, which is why the command runs as the service role and is told who is acting; it checks that
// member's `quotes.send` and `conversations.send` itself.
//
// Answers with the refusal to return, or null once the email is queued.
export async function sendDraftQuoteByEmail(input: {
	organizationId: string;
	actorUserId: string;
	quoteId: string;
	expectedRevision: number;
	idempotencyKey: string;
}): Promise<Response | null> {
	const ownerClient = getOwnerSupabaseClient();
	try {
		// The same bucket as the Quote page's own Send email: it is the same act by the same person.
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_quote_email:${input.organizationId}:${input.actorUserId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

		// A second, independent link for the billing contact; the command only spends it when the client
		// has one, exactly as the published-quote email does.
		const link = createQuoteEmailAccessLink();
		const billingLink = createQuoteEmailAccessLink();
		const { error } = await ownerClient.rpc('send_draft_quote_email', {
			target_organization_id: input.organizationId,
			target_actor_user_id: input.actorUserId,
			target_quote_id: input.quoteId,
			expected_revision: input.expectedRevision,
			target_logical_send_key: input.idempotencyKey,
			target_quote_url: link.url,
			target_quote_token_hash: link.tokenHash,
			target_billing_quote_url: billingLink.url,
			target_billing_quote_token_hash: billingLink.tokenHash
		});
		if (error) return emailSendPrerequisiteResponse(error) ?? quoteWriteError(error);
		return null;
	} catch (error) {
		console.error('Could not send the draft quote by email.', error);
		return json(
			{ error: 'The quote email could not be sent. The quote is still a draft.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
}
