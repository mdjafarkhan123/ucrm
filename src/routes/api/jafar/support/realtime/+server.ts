import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The secret live channel this /jafar session listens on for Support Inbox activity. The /jafar login is not
// a Supabase sign-in, so the channel name itself is the pass, the way Website Chat visitors get theirs. It
// is issued once per owner session, reused on every call, and stops working when the session ends. There is
// no request body to validate: the session cookie is the whole input.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const { data, error } = await getOwnerSupabaseClient().rpc('issue_support_realtime_grant', {
		target_owner_session_id: session.sessionId
	});
	if (error || !data) {
		if (error?.code === '42501') return ownerUnauthorized();
		console.error('Could not issue the Support Inbox live channel.', error);
		return json({ error: 'Live updates could not be started.' }, { status: 500 });
	}

	return json({ topic: data }, { headers: { 'cache-control': 'no-store' } });
};
