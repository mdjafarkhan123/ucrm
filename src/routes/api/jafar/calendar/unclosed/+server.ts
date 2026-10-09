import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Jafar business management C2: calls that have ended and still wait for "How did it go?", oldest first. D3b: the
// viewer's own calls.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_unclosed_calls', {
		limit_count: 20,
		viewer_member_id: session.memberId ?? undefined
	});
	if (error) {
		console.error('Could not load calls waiting for an outcome.', error);
		return json({ error: 'Calls waiting for an outcome could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: PRIVATE_READ_HEADERS });
};
