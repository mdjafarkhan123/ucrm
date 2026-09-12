import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { drainFormSubmissionQueue } from '$lib/server/forms/submission-worker';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().FORM_SUBMISSION_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// One form-submission wake: drain the pending queue through process_next_form_submission until idle.
// Secret-gated like the other internal workers. No single-flight lease needed -- the RPC's own per-row
// `for update skip locked` claim is the exactly-once boundary, so overlapping wakes are safe.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const result = await drainFormSubmissionQueue({});
	return json(result, { headers: { 'cache-control': 'no-store' } });
};
