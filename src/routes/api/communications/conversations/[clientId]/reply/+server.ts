import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { hasPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES } from '$lib/server/communications/inbound-email';
import { renderManualEmailHtml } from '$lib/server/communications/manual-email';
import {
	OutboundAttachmentError,
	resolveLibraryFileAttachments,
	resolveOutboundAttachments,
	resolveOutboundSmsAttachment,
	type ResolvedOutboundAttachment
} from '$lib/server/communications/outbound-attachments';
import { createSmsAttachmentSecureLink } from '$lib/server/communications/sms-attachment-access-links';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	conversationReplyEmailSchema,
	conversationReplySmsSchema
} from '$lib/server/validation/communications.schema';

// A database rejection surfaced as a 422 with its own message: permission, missing recipient, sender/number
// not ready, or (SMS only) a P0001 safety refusal (consent, balance, quiet hours) or a same-key payload
// conflict. Anything else is an unexpected failure, logged and hidden behind a generic error.
const KNOWN_REJECTION_CODES = ['42501', '23503', '55000', '23514', 'P0001', '23505'];

// Sends a reply from an already-open Conversations thread, email or SMS. Unlike the client-detail manual-
// email dialog, the recipient is never browser-chosen -- enqueue_conversation_reply_email/_sms resolve it
// from the conversation's own most recent activity, so this route only ever passes ids and plain text.
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
	const channel = (body as { channel?: unknown } | null)?.channel === 'sms' ? 'sms' : 'email';

	const smsParsed = channel === 'sms' ? conversationReplySmsSchema.safeParse(body) : null;
	const emailParsed = channel === 'email' ? conversationReplyEmailSchema.safeParse(body) : null;
	const parseFailure = smsParsed ?? emailParsed;
	if (parseFailure && !parseFailure.success) {
		return json(
			{
				error: 'Please review the reply details.',
				field_errors: communicationFieldErrors(parseFailure.error)
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

		if (smsParsed && smsParsed.success) {
			const [file] = smsParsed.data.attachments;
			const [libraryFileId] = smsParsed.data.library_file_ids;
			if (file && libraryFileId) {
				return validationError({ attachments: 'Attach at most one file to a text message.' });
			}

			let smsAttachments: (ResolvedOutboundAttachment & {
				access_token_hash: string;
				link_url: string;
			})[];
			try {
				let resolved: ResolvedOutboundAttachment | null = null;
				if (file) {
					resolved = await resolveOutboundSmsAttachment(organizationId, file);
				} else if (libraryFileId) {
					[resolved] = await resolveLibraryFileAttachments(event.locals.supabase, [libraryFileId]);
					if (resolved.byte_size > INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES) {
						throw new OutboundAttachmentError(
							'A file must be 20 MB or smaller to send as a text message.'
						);
					}
				}
				if (resolved) {
					// Made ahead of the enqueue call, always -- the command decides afterwards whether the
					// picture could go as real MMS. An unused token (real MMS was possible) is simply never
					// persisted; see sms-attachment-access-links.ts's own header note.
					const { tokenHashHex, url } = createSmsAttachmentSecureLink();
					smsAttachments = [{ ...resolved, access_token_hash: tokenHashHex, link_url: url }];
				} else {
					smsAttachments = [];
				}
			} catch (error) {
				if (error instanceof OutboundAttachmentError) {
					return validationError({ attachments: error.message });
				}
				throw error;
			}

			const { data, error } = await ownerClient.rpc('enqueue_conversation_reply_sms', {
				target_organization_id: organizationId,
				target_actor_user_id: check.auth.user.id,
				target_client_id: clientId,
				target_logical_send_key: smsParsed.data.idempotency_key,
				target_body: smsParsed.data.body,
				target_attachments: smsAttachments
			});
			if (error) {
				const dbError = error as { code?: string; message?: string };
				if (KNOWN_REJECTION_CODES.includes(dbError.code ?? '')) {
					return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
				}
				console.error('Could not queue an SMS conversation reply.', error);
				return databaseError();
			}

			// Best-effort: the text has already gone out with the real file content embedded above, so a
			// failure here only means the File's "Used in" list will not mention this text -- worth logging,
			// never worth undoing an already-sent message over.
			if (libraryFileId) {
				const { error: linkError } = await ownerClient.rpc('attach_file_to_record', {
					target_organization_id: organizationId,
					target_file_id: libraryFileId,
					target_actor_id: check.auth.user.id,
					target_entity_type: 'message',
					target_entity_id: data.id
				});
				if (linkError) console.error('Could not link a library file to a sent text.', linkError);
			}

			return json(
				{ intent: { id: data.id, status: data.status, created_at: data.created_at } },
				{ status: 201, headers: NO_STORE_HEADERS }
			);
		}

		// Unreachable: channel === 'email' here (the sms branch above already returned), and a failed email
		// parse already returned above too -- this only narrows the type for what follows.
		if (!emailParsed?.success) return databaseError();
		const input = emailParsed.data;

		let attachments: ResolvedOutboundAttachment[];
		try {
			const [rawAttachments, libraryAttachments] = await Promise.all([
				resolveOutboundAttachments(organizationId, input.attachments),
				resolveLibraryFileAttachments(event.locals.supabase, input.library_file_ids)
			]);
			attachments = [...rawAttachments, ...libraryAttachments];
			const totalBytes = attachments.reduce((sum, item) => sum + item.byte_size, 0);
			if (totalBytes > INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES) {
				throw new OutboundAttachmentError('Attachments must total 20 MB or less.');
			}
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
			target_attachments: attachments,
			target_available_at: input.scheduled_at
		});
		if (error) {
			const dbError = error as { code?: string; message?: string };
			if (KNOWN_REJECTION_CODES.includes(dbError.code ?? '')) {
				return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
			}
			console.error('Could not queue a conversation reply.', error);
			return databaseError();
		}

		// Best-effort: the email has already gone out with the real file content embedded above, so a
		// failure here only means the File's "Used in" list will not mention this email -- worth logging,
		// never worth undoing an already-sent message over.
		for (const fileId of input.library_file_ids) {
			const { error: linkError } = await ownerClient.rpc('attach_file_to_record', {
				target_organization_id: organizationId,
				target_file_id: fileId,
				target_actor_id: check.auth.user.id,
				target_entity_type: 'message',
				target_entity_id: data.id
			});
			if (linkError) console.error('Could not link a library file to a sent email.', linkError);
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
