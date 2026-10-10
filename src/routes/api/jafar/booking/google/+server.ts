import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { disconnectGoogle, googleStatus } from '$lib/server/jafar/google';

// Jafar business management E5: whether Jafar's Google is connected, and disconnecting it. Not in any team area, so
// only Jafar reaches it. Disconnecting keeps the meetings already made; new Google bookings then say the link will follow.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	try {
		return json(await googleStatus(getOwnerSupabaseClient()), { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the Google connection.', error);
		return json({ error: 'The Google connection could not be loaded.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	try {
		const client = getOwnerSupabaseClient();
		await disconnectGoogle(client);
		return json(await googleStatus(client));
	} catch (error) {
		console.error('Could not disconnect Google.', error);
		return databaseError();
	}
};
