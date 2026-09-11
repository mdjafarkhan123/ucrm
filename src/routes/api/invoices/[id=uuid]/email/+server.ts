import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { createInvoiceEmailAccessLink } from '$lib/server/communications/invoice-email';
import { emailSendPrerequisiteResponse } from '$lib/server/communications/email-send-errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { updateInvoiceError } from '$lib/server/invoices/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { invoiceEmailSchema } from '$lib/server/validation/invoices.schema';

// Emailing an issued invoice to the client. The invoice is issued first by the caller (issue_invoice, method
// 'sent'); this only delivers. The enqueue command checks the invoice, recipient, sender and allowance again,
// generates the customer's door, and queues one email — idempotent on the send key so a double click does not
// send twice. Delivery boundary matches the quote email route: invoices.send plus conversations.send.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.send');
	if ('response' in check) return check.response;

	// Sending an invoice by email also opens a customer conversation. Keep the route aligned with the command
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
	const parsed = invoiceEmailSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_invoice_email:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

		const link = createInvoiceEmailAccessLink();
		const { data, error } = await ownerClient.rpc('enqueue_invoice_communication_email', {
			target_organization_id: check.auth.organization.id,
			target_actor_user_id: check.auth.user.id,
			target_invoice_id: event.params.id,
			target_logical_send_key: parsed.data.idempotency_key,
			target_invoice_url: link.url,
			target_invoice_token_hash: link.tokenHash
		});
		if (error) return emailSendPrerequisiteResponse(error) ?? updateInvoiceError(error);
		return json(
			{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not queue invoice email.', error);
		return json(
			{ error: 'The invoice email could not be queued.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
