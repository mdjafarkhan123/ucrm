import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { drainImportQueue } from '$lib/server/imports/import-worker';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().CLIENT_IMPORT_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// One client-import wake: drain the ready queue through process_next_import_row until idle, and build the error
// file for any batch that finished. Secret-gated like the other internal workers. No single-flight lease
// needed -- the RPC's own per-row `for update skip locked` claim is the exactly-once boundary, so overlapping
// wakes (the commit nudge and the minute cron sweep) are safe.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const result = await drainImportQueue({});
	return json(result, { headers: { 'cache-control': 'no-store' } });
};
