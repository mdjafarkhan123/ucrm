import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import { recordOperationOutcome } from './outbox';
import type { TargetKind } from './event-types';

type EmailPayload = { subject: string; html_content: string; text_content: string };

/**
 * Enqueues a durable outbox row for an email that must not be lost to a Brevo outage, then
 * attempts to send it immediately. The full rendered content is stored in the row itself, so
 * a later retry from the Operations screen re-sends the exact same email without needing the
 * caller to regenerate it. Enqueuing twice with the same idempotencyKey reuses the same row
 * instead of sending a duplicate email.
 */
export async function enqueueEmailDelivery(
	client: SupabaseClient<Database>,
	params: {
		templateKey: string;
		target: { targetKind: TargetKind; targetId: string | null };
		idempotencyKey: string;
		recipientEmail: string;
		subject: string;
		htmlContent: string;
		textContent: string;
	}
) {
	const { data: existing, error: lookupError } = await client
		.from('platform_outbox_deliveries')
		.select('id')
		.eq('idempotency_key', params.idempotencyKey)
		.maybeSingle();
	if (lookupError) throw lookupError;

	let deliveryId: string;
	if (existing) {
		deliveryId = existing.id;
	} else {
		const { data: inserted, error } = await client
			.from('platform_outbox_deliveries')
			.insert({
				template_key: params.templateKey,
				target_kind: params.target.targetKind,
				target_id: params.target.targetId,
				idempotency_key: params.idempotencyKey,
				recipient_email: params.recipientEmail,
				payload: {
					subject: params.subject,
					html_content: params.htmlContent,
					text_content: params.textContent
				} satisfies EmailPayload
			})
			.select('id')
			.single();
		if (error) throw error;
		deliveryId = inserted.id;
	}

	await dispatchOutboxDelivery(client, deliveryId);
	return deliveryId;
}

/**
 * Re-sends the exact content stored on a queued delivery row. Used for both the initial send and
 * later retries. `actorEmail` is only supplied when a human explicitly triggered this attempt (an
 * owner retrying from Operations) -- the original automated enqueue has no human actor to attribute.
 */
export async function dispatchOutboxDelivery(
	client: SupabaseClient<Database>,
	deliveryId: string,
	actorEmail?: string
) {
	const { data: delivery, error: loadError } = await client
		.from('platform_outbox_deliveries')
		.select('id, recipient_email, attempt_count, target_kind, target_id, correlation_id, payload, status')
		.eq('id', deliveryId)
		.maybeSingle();
	if (loadError) throw loadError;
	if (!delivery) throw new Error('The queued delivery does not exist.');
	if (delivery.status === 'sent') return;

	const payload = delivery.payload as EmailPayload;
	const target = { targetKind: delivery.target_kind as TargetKind, targetId: delivery.target_id };

	try {
		await sendTransactionalEmail({
			to: { email: delivery.recipient_email },
			subject: payload.subject,
			htmlContent: payload.html_content,
			textContent: payload.text_content
		});
		await client
			.from('platform_outbox_deliveries')
			.update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null })
			.eq('id', deliveryId);
		await recordOperationOutcome(client, {
			operationType: 'outbox_email_delivery',
			idempotencyKey: deliveryId,
			target,
			success: true
		});
	} catch (error) {
		const message = error instanceof Error ? error.message : 'The email could not be sent.';
		await client
			.from('platform_outbox_deliveries')
			.update({
				status: 'failed',
				attempt_count: delivery.attempt_count + 1,
				last_error: message.slice(0, 500)
			})
			.eq('id', deliveryId);
		await recordOperationOutcome(client, {
			operationType: 'outbox_email_delivery',
			idempotencyKey: deliveryId,
			target,
			actorEmail,
			success: false,
			error
		});
		throw error;
	}
}
