import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTwilioProvisioningStore } from '$lib/server/communications/twilio-provisioning-store';
import {
	collectTwilioValidationTokens,
	getTwilioStatusWebhookUrl,
	parseTwilioStatusParams,
	statusEventKey,
	validateTwilioSignature
} from '$lib/server/communications/twilio-webhook';

const NO_STORE = { 'cache-control': 'no-store' } as const;

// Accepted (recorded, or a harmless duplicate/unresolved). Twilio needs no body.
const accepted = () => new Response(null, { status: 204, headers: NO_STORE });
// Signature could not be proven -- forged AccountSid, wrong/expired token, or a bad signature. Never say why.
const forbidden = () => new Response(null, { status: 403, headers: NO_STORE });
// The event is real but not yet durably stored: fail so Twilio resends rather than dropping it silently.
const retryLater = () => new Response(null, { status: 500, headers: NO_STORE });

export const POST: RequestHandler = async ({ request }) => {
	// Twilio status callbacks are application/x-www-form-urlencoded; the signature covers ALL POST params,
	// so we keep the full set for validation and storage, not just the identifying three.
	let params: Record<string, string>;
	try {
		const form = await request.formData();
		params = {};
		for (const [key, value] of form.entries()) {
			if (typeof value === 'string') params[key] = value;
		}
	} catch {
		return forbidden();
	}

	const identifiers = parseTwilioStatusParams(params);
	if (!identifiers) return forbidden();

	const client = getOwnerSupabaseClient();
	const store = createSupabaseTwilioProvisioningStore(client);

	// AccountSid-lookup-then-validate: the AccountSid is read from the *unvalidated* form only as a key to
	// load that subaccount's Auth Token(s). A forged AccountSid loads the wrong (or no) token, so the
	// signature check below fails and the request is rejected -- safe and standard.
	const account = await store.getAccountBySubaccountSid(identifiers.AccountSid);
	if (!account) return forbidden();

	const tokens = await collectTwilioValidationTokens(store, account.id, {
		organizationId: account.organizationId,
		subaccountSid: account.subaccountSid
	});

	const valid = validateTwilioSignature(
		tokens,
		request.headers.get('x-twilio-signature'),
		getTwilioStatusWebhookUrl(),
		params
	);
	if (!valid) return forbidden();

	// Resolve the delivery intent this status belongs to, scoped to the signing org. An unknown MessageSid
	// (a status for a message we never sent, or one that arrived before its intent) resolves to null: still
	// recorded on the spine, projected by nothing.
	const { data: intent } = await client
		.from('communication_delivery_intents')
		.select('id')
		.eq('organization_id', account.organizationId)
		.eq('channel', 'sms')
		.eq('provider_message_id', identifiers.MessageSid)
		.maybeSingle();

	const { error: insertError } = await client
		.from('communication_provider_callback_events')
		.insert({
			provider: 'twilio',
			channel: 'sms',
			provider_event_key: statusEventKey(identifiers),
			delivery_intent_id: intent?.id ?? null,
			event_kind: identifiers.MessageStatus,
			occurred_at: null,
			payload: params as Json
		});

	// A duplicate (same message + status) is the idempotent happy path: already durably recorded.
	if (insertError && insertError.code !== '23505') {
		console.error('Could not record a Twilio status callback; asking the provider to retry.', {
			code: insertError.code
		});
		return retryLater();
	}

	// On-arrival projection so an open inbox reflects delivered/failed within a second instead of waiting for
	// the cron. Best effort and idempotent (bounded batch, processed_at gate, SKIP LOCKED); the cron remains
	// the safety net, and a failure here never fails the durable insert above.
	try {
		const { error: drainError } = await client.rpc('process_communication_sms_provider_callbacks', {
			batch_size: 25
		});
		if (drainError)
			console.error(
				'On-arrival SMS callback processing failed; the cron will catch up.',
				drainError
			);
	} catch (drainError) {
		console.error('On-arrival SMS callback processing failed; the cron will catch up.', drainError);
	}

	return accepted();
};
