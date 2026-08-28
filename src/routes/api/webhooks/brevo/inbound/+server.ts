import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { bearerMatches } from '$lib/server/communications/brevo-webhook';
import {
	attachmentExtension,
	candidateRecipients,
	classifyInboundMessageKind,
	DANGEROUS_ATTACHMENT_EXTENSIONS,
	inboundEventDedupeKey,
	INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES,
	parseBrevoInboundWebhook,
	type BrevoInboundItem
} from '$lib/server/communications/inbound-email';

type InboundMessageRow = {
	id: string;
	organization_id: string;
};

async function ingestItem(
	client: ReturnType<typeof getOwnerSupabaseClient>,
	item: BrevoInboundItem
) {
	const { data: callbackEvent, error: callbackError } = await client
		.from('communication_provider_callback_events')
		.insert({
			provider_event_key: inboundEventDedupeKey(item),
			event_kind: 'inbound_email',
			occurred_at: item.SentAtDate ? new Date(item.SentAtDate).toISOString() : null,
			payload: item as Json
		})
		.select('id')
		.single();

	if (callbackError?.code === '23505') return { duplicate: true };
	if (callbackError) {
		console.error('Could not record a Brevo inbound webhook item.', callbackError);
		return { duplicate: false };
	}

	const { data: inboundMessage, error: rpcError } = await client.rpc(
		'record_communication_inbound_message',
		{
			target_provider_message_id: item.MessageId,
			target_in_reply_to_provider_message_id: item.InReplyTo,
			target_provider_callback_event_id: callbackEvent?.id,
			target_sender_email: item.From.Address.trim().toLowerCase(),
			target_sender_name: item.From.Name,
			target_to_recipients: item.To as unknown as Json,
			target_cc_recipients: item.Cc as unknown as Json,
			target_subject: item.Subject,
			target_html_content: item.RawHtmlBody,
			target_text_content: item.RawTextBody ?? '',
			target_message_kind: classifyInboundMessageKind(item),
			target_candidate_recipients: candidateRecipients(item) as unknown as Json
		}
	);

	if (rpcError) {
		console.error('Could not resolve a Brevo inbound message.', rpcError);
		return { duplicate: false };
	}

	const inserted = inboundMessage as InboundMessageRow | null;
	if (!inserted || item.Attachments.length === 0) return { duplicate: false };

	const totalSize = item.Attachments.reduce((sum, attachment) => sum + attachment.ContentLength, 0);
	const oversized = totalSize > INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES;

	const attachmentRows = item.Attachments.map((attachment) => {
		const dangerous = DANGEROUS_ATTACHMENT_EXTENSIONS.has(attachmentExtension(attachment.Name));
		const status = oversized ? 'blocked_size' : dangerous ? 'blocked_type' : 'pending_import';
		return {
			organization_id: inserted.organization_id,
			inbound_message_id: inserted.id,
			file_name: attachment.Name,
			mime_type: attachment.ContentType,
			byte_size: attachment.ContentLength,
			status,
			provider_download_token: status === 'pending_import' ? attachment.DownloadToken : null
		};
	});

	const { error: attachmentError } = await client
		.from('communication_inbound_attachments')
		.insert(attachmentRows);
	if (attachmentError) console.error('Could not record inbound attachments.', attachmentError);

	return { duplicate: false };
}

export const POST: RequestHandler = async ({ request }) => {
	if (!bearerMatches(request.headers.get('authorization'), env.BREVO_INBOUND_WEBHOOK_TOKEN))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json(
			{ error: 'Webhook body must be valid JSON.' },
			{ status: 400, headers: { 'cache-control': 'no-store' } }
		);
	}

	const items = parseBrevoInboundWebhook(raw);
	if (!items)
		return json(
			{ error: 'Webhook payload was invalid.' },
			{ status: 422, headers: { 'cache-control': 'no-store' } }
		);

	const client = getOwnerSupabaseClient();
	// Every item is ingested independently through its own idempotent callback-event insert, so one
	// malformed or already-seen item in a batch never blocks the rest, a full-batch retry is safe, and
	// a multi-item batch does not pay for each item's round trips sequentially.
	await Promise.all(items.map((item) => ingestItem(client, item)));

	return json({ accepted: true }, { headers: { 'cache-control': 'no-store' } });
};
