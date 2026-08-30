import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	bearerMatches,
	eventKey,
	intentIdFromTags,
	parseBrevoWebhookEvent
} from '$lib/server/communications/brevo-webhook';

export const POST: RequestHandler = async ({ request }) => {
	if (!bearerMatches(request.headers.get('authorization'), env.BREVO_TRANSACTIONAL_WEBHOOK_TOKEN))
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
	const event = parseBrevoWebhookEvent(raw);
	if (!event)
		return json(
			{ error: 'Webhook payload was invalid.' },
			{ status: 422, headers: { 'cache-control': 'no-store' } }
		);

	const client = getOwnerSupabaseClient();
	const intentId = intentIdFromTags(event.tags);
	const { error } = await client.from('communication_provider_callback_events').insert({
		provider_event_key: eventKey(event),
		delivery_intent_id: intentId,
		event_kind: event.event,
		occurred_at: event.ts_event ? new Date(event.ts_event * 1000).toISOString() : null,
		payload: event as Json
	});
	if (error?.code === '23505')
		return json({ accepted: true, duplicate: true }, { headers: { 'cache-control': 'no-store' } });
	if (error) {
		// A storage failure here is transient: the event is real and not yet durably recorded, so ask
		// Brevo to retry rather than dropping it. 429 is the provider's back-off-and-resend signal.
		console.error(
			'Could not record Brevo transactional webhook; asking the provider to retry.',
			error
		);
		return json(
			{ error: 'Webhook could not be recorded yet. Please retry.' },
			{ status: 429, headers: { 'cache-control': 'no-store', 'retry-after': '60' } }
		);
	}

	// R1 live inbox: flip the delivery intent's status on arrival instead of waiting for the 2-minute
	// cron, so an open inbox shows delivered/bounced within a second (the outcome update fires the
	// realtime broadcast trigger). Best effort and idempotent: this drains only a small bounded batch of
	// still-unprocessed callbacks (FOR UPDATE SKIP LOCKED, processed_at guard), and the cron remains the
	// safety net -- a failure or timeout here never fails the durable insert above.
	try {
		const { error: drainError } = await client.rpc('process_communication_provider_callbacks', {
			batch_size: 25
		});
		if (drainError)
			console.error('On-arrival callback processing failed; the cron will catch up.', drainError);
	} catch (drainError) {
		console.error('On-arrival callback processing failed; the cron will catch up.', drainError);
	}

	return json({ accepted: true }, { headers: { 'cache-control': 'no-store' } });
};
