import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { hasPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { renderManualEmailHtml } from '$lib/server/communications/manual-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	forwardInboundMessageSchema
} from '$lib/server/validation/communications.schema';

// Forwards one already-resolved inbound message to external recipients. Unlike a reply, the recipients
// are always browser-chosen (an external address is never a saved contact method), and the database
// command itself validates attachment_ids against the source message's own already-imported attachments
// -- no resolveOutboundAttachments-style helper needed here.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.forward');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	const { clientId, messageId } = event.params;
	if (!clientId || !messageId) return validationError({ form: 'Choose a valid message.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = forwardInboundMessageSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the forward details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_message_forward:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;

		const { data, error } = await ownerClient.rpc('enqueue_inbound_message_forward', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_source_inbound_message_id: messageId,
			target_logical_send_key: input.idempotency_key,
			target_recipient_emails: input.recipients,
			target_subject: input.subject,
			target_html_content: renderManualEmailHtml(input.body),
			target_text_content: input.body,
			target_attachment_ids: input.attachment_ids
		});
		if (error) {
			const dbError = error as { code?: string; message?: string };
			if (['42501', '23503', '55000', '23514', 'P0002'].includes(dbError.code ?? '')) {
				return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
			}
			console.error('Could not queue a message forward.', error);
			return databaseError();
		}

		return json(
			{ event: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not queue a message forward.', error);
		return databaseError();
	}
};
