import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';

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

	// Sender identities are a Part 2 dependency. Do not claim a row until one can be rechecked: a claim
	// without submission would strand a message in processing and make a later retry ambiguous.
	return json(
		{ ready: false, reason: 'sender_identity_not_available' },
		{ status: 503, headers: { 'cache-control': 'no-store' } }
	);
};
