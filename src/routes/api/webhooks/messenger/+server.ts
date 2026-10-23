import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	messengerBodySha256,
	messengerHandshakeChallenge,
	readCappedBody,
	verifyMessengerSignature
} from '$lib/server/communications/messenger-webhook';
import { drainMessengerWebhookEvents } from '$lib/server/communications/messenger-inbound-worker';

const NO_STORE = { 'cache-control': 'no-store' } as const;
const ok = () => new Response(null, { status: 200, headers: NO_STORE });
// Not provably from Meta. Never say why.
const forbidden = () => new Response(null, { status: 403, headers: NO_STORE });
const tooLarge = () => new Response(null, { status: 413, headers: NO_STORE });
// Real, but not yet saved: fail so Meta resends rather than losing it.
const retryLater = () => new Response(null, { status: 500, headers: NO_STORE });

// Meta's subscription handshake, run once when the callback URL is saved in the app dashboard.
export const GET: RequestHandler = async ({ url }) => {
	const challenge = messengerHandshakeChallenge(url.searchParams, env.MESSENGER_VERIFY_TOKEN);
	if (!challenge) return forbidden();
	return new Response(challenge, {
		status: 200,
		headers: { ...NO_STORE, 'content-type': 'text/plain' }
	});
};

// One app-wide endpoint for every connected Page: each entry names its Page, which names the business. The
// request only proves the signature and saves the exact delivery, then answers well inside Meta's 5 seconds;
// Meta switches the webhook off after an hour of failures, so no client lookup ever runs here.
export const POST: RequestHandler = async ({ request }) => {
	const body = await readCappedBody(request);
	if (!body) return tooLarge();
	if (
		!verifyMessengerSignature(body, request.headers.get('x-hub-signature-256'), env.META_APP_SECRET)
	)
		return forbidden();

	let payload: unknown;
	try {
		payload = JSON.parse(Buffer.from(body).toString('utf8'));
	} catch {
		// Signed by Meta yet unreadable: retrying would not help.
		return ok();
	}
	if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return ok();

	// A retry carries the same bytes, so the body hash makes it the same row.
	const { error } = await getOwnerSupabaseClient()
		.from('communication_messenger_webhook_events')
		.upsert(
			{
				body_sha256: `\\x${messengerBodySha256(body).toString('hex')}`,
				payload: payload as never
			},
			{ onConflict: 'body_sha256', ignoreDuplicates: true }
		);
	if (error) {
		console.error('Could not save a Messenger delivery; asking Meta to retry.', {
			code: error.code
		});
		return retryLater();
	}

	void drainMessengerWebhookEvents().catch((drainError) =>
		console.error(
			'Messenger instant processing failed; the one-minute cron will retry.',
			drainError
		)
	);
	return ok();
};
