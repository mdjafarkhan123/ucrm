import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { hasPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { renderManualEmailHtml } from '$lib/server/communications/manual-email';
import {
	OutboundAttachmentError,
	resolveOutboundAttachments
} from '$lib/server/communications/outbound-attachments';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	conversationReplyEmailSchema
} from '$lib/server/validation/communications.schema';

// Sends a reply from an already-open Conversations thread. Unlike the client-detail manual-email
// dialog, the recipient is never browser-chosen -- enqueue_conversation_reply_email resolves it from
// the conversation's own most recent activity, so this route only ever passes ids and plain text.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = conversationReplyEmailSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the reply details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_conversation_reply:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;

		let attachments;
		try {
			attachments = await resolveOutboundAttachments(organizationId, input.attachments);
		} catch (error) {
			if (error instanceof OutboundAttachmentError) {
				return validationError({ attachments: error.message });
			}
			throw error;
		}

		const { data, error } = await ownerClient.rpc('enqueue_conversation_reply_email', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_client_id: clientId,
			target_logical_send_key: input.idempotency_key,
			target_subject: input.subject,
			target_html_content: renderManualEmailHtml(input.body),
			target_text_content: input.body,
			target_attachments: attachments
		});
		if (error) {
			const dbError = error as { code?: string; message?: string };
			if (['42501', '23503', '55000', '23514'].includes(dbError.code ?? '')) {
				return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
			}
			console.error('Could not queue a conversation reply.', error);
			return databaseError();
		}

		// R2: an AFTER INSERT trigger on the outbox fires the immediate drain automatically, so this route no
		// longer nudges by hand. See migration communications_email_outbox_wake_on_insert_trigger.
		return json(
			{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not queue a conversation reply.', error);
		return databaseError();
	}
};
