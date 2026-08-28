import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { runCommunicationInboundAttachmentWorker } from '$lib/server/communications/inbound-attachment-worker';

// One pg_cron tick may find more than one claimable batch (batch_size 20); loop until a claim comes
// back empty so a burst of inbound mail drains in one invocation instead of waiting for the next tick.
const MAX_BATCHES_PER_INVOCATION = 25;

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().COMMUNICATIONS_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	let batches = 0;
	let claimed = 0;
	let imported = 0;
	let failed = 0;

	while (batches < MAX_BATCHES_PER_INVOCATION) {
		const result = await runCommunicationInboundAttachmentWorker();
		batches += 1;
		claimed += result.claimed;
		imported += result.imported;
		failed += result.failed;
		if (result.claimed === 0) break;
	}

	return json({ batches, claimed, imported, failed }, { headers: { 'cache-control': 'no-store' } });
};
