import { randomUUID } from 'node:crypto';
import type { RequestHandler } from './$types';
import { getSesEnv, sesInboundTopicArn } from '$lib/server/communications/ses-env';
import {
	awsSnsSignatureCheck,
	trustedSubscribeUrl,
	verifySnsMessage
} from '$lib/server/communications/sns-webhook';
import { runMonitoredSesInboundWake } from '$lib/server/communications/ses-inbound-worker';

const NO_STORE = { 'cache-control': 'no-store' } as const;
const ok = () => new Response(null, { status: 200, headers: NO_STORE });
// Not provably from our SNS topic. Never say why.
const forbidden = () => new Response(null, { status: 403, headers: NO_STORE });
// Subscription confirmation did not reach SNS: fail so SNS resends it.
const retryLater = () => new Response(null, { status: 502, headers: NO_STORE });

// Instant wake for customer email replies. The ucrm-ses-inbound topic fans out to the durable SQS queue AND to
// this HTTPS endpoint; the push carries nothing we store -- it only starts the same lease-guarded drain the
// one-minute cron runs, so a reply is read from SQS within seconds instead of waiting for the next cron tick.
// If this endpoint is down, the message is still in SQS and the cron picks it up.
export const POST: RequestHandler = async ({ request }) => {
	const env = getSesEnv();
	const envelope = await verifySnsMessage(
		await request.text(),
		sesInboundTopicArn(env),
		awsSnsSignatureCheck(env.AWS_SES_REGION)
	);
	if (!envelope) return forbidden();

	if (envelope.Type === 'SubscriptionConfirmation') {
		const subscribeUrl = trustedSubscribeUrl(envelope.SubscribeURL, env.AWS_SES_REGION);
		if (!subscribeUrl) return forbidden();
		try {
			const confirmed = await fetch(subscribeUrl, { signal: AbortSignal.timeout(10_000) });
			return confirmed.ok ? ok() : retryLater();
		} catch {
			return retryLater();
		}
	}

	if (envelope.Type === 'Notification') {
		// Answer SNS now (its HTTPS timeout is shorter than a drain's long poll) and drain in the background. A
		// wake that finds a drain already running is fine: that drain is long-polling the same queue.
		void runMonitoredSesInboundWake({ wakeCorrelationId: randomUUID() }).catch((error) =>
			console.error('SES inbound push wake failed; the one-minute cron will retry.', error)
		);
	}

	return ok();
};
