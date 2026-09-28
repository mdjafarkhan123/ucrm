import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { emailSendPrerequisiteResponse } from '$lib/server/communications/email-send-errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { updateInvoiceError } from '$lib/server/invoices/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

// Emailing the client that a voided invoice is cancelled (decision D9). Called by the Void dialog straight after
// a successful void when its checkbox is ticked, and again from the voided invoice if that send was skipped or
// failed. There is no body: the command fixes the send key per invoice, so a retry or double click can never
// send a second notice, and it re-checks that the bill is voided and was issued to the client.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.void');
	if ('response' in check) return check.response;

	if (!hasPermission(check.access, 'conversations.send')) {
		return json(
			{ error: 'You do not have access to email clients.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_invoice_email:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

		const { data, error } = await ownerClient.rpc('enqueue_invoice_void_notice_email', {
			target_organization_id: check.auth.organization.id,
			target_actor_user_id: check.auth.user.id,
			target_invoice_id: event.params.id
		});
		if (error) return emailSendPrerequisiteResponse(error) ?? updateInvoiceError(error);
		return json(
			{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not queue the invoice cancellation email.', error);
		return json(
			{ error: 'The cancellation email could not be queued.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
