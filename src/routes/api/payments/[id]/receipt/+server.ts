import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { createPaymentReceiptEmailAccessLink } from '$lib/server/communications/receipt-email';
import { emailSendPrerequisiteResponse } from '$lib/server/communications/email-send-errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { updateInvoiceError } from '$lib/server/invoices/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { paymentReceiptEmailSchema } from '$lib/server/validation/invoices.schema';

// Emailing the customer their receipt for a recorded payment. The enqueue command re-checks the payment,
// recipient, sender and allowance, generates the customer's door, and queues one email as a hosted link —
// idempotent on the send key so a double click does not send twice, while a deliberate resend (a fresh key)
// sends again. Boundary mirrors the invoice email route: invoices.record_payment plus conversations.send.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.record_payment');
	if ('response' in check) return check.response;

	// Sending a receipt by email also opens a customer conversation. Keep the route aligned with the command
	// so a direct request cannot reach a service-only RPC that will necessarily refuse it.
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
	const parsed = paymentReceiptEmailSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_payment_receipt_email:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

		const link = createPaymentReceiptEmailAccessLink();
		const { data, error } = await ownerClient.rpc('enqueue_payment_receipt_email', {
			target_organization_id: check.auth.organization.id,
			target_actor_user_id: check.auth.user.id,
			target_payment_event_id: event.params.id,
			target_logical_send_key: parsed.data.idempotency_key,
			target_receipt_url: link.url,
			target_receipt_token_hash: link.tokenHash
		});
		if (error) return emailSendPrerequisiteResponse(error) ?? updateInvoiceError(error);
		return json(
			{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not queue payment receipt email.', error);
		return json(
			{ error: 'The receipt email could not be queued.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
