import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import { runMemberIdentityWorker } from '$lib/server/team/member-identity-worker';

const NO_STORE_HEADERS = { 'cache-control': 'no-store' };

function isAuthorized(request: Request) {
	const authorization = request.headers.get('authorization') ?? '';
	const [scheme, token] = authorization.split(' ');
	if (scheme !== 'Bearer' || !token) return false;

	const configuredSecret = getServerEnv().TEAM_MEMBER_IDENTITY_WORKER_SECRET;
	if (!configuredSecret) return false;

	const expected = Buffer.from(configuredSecret);
	const provided = Buffer.from(token);
	return provided.length === expected.length && timingSafeEqual(provided, expected);
}

export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401, headers: NO_STORE_HEADERS });
	}

	try {
		const result = await runMemberIdentityWorker(getOwnerSupabaseClient());
		return json(result, { headers: NO_STORE_HEADERS });
	} catch {
		return json(
			{ error: 'The member identity cleanup worker failed.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
