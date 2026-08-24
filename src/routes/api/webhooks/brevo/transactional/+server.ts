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
		console.error('Could not record Brevo transactional webhook.', error);
		return json(
			{ error: 'Webhook could not be recorded.' },
			{ status: 500, headers: { 'cache-control': 'no-store' } }
		);
	}

	return json({ accepted: true }, { headers: { 'cache-control': 'no-store' } });
};
