import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { disconnectZoom, zoomStatus } from '$lib/server/jafar/zoom';

// Jafar business management E4b: whether Jafar's Zoom is connected, and disconnecting it. Not in any team area, so
// only Jafar reaches it. Disconnecting keeps the meetings already made; new Zoom bookings then say the link will follow.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	try {
		return json(await zoomStatus(getOwnerSupabaseClient()), { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the Zoom connection.', error);
		return json({ error: 'The Zoom connection could not be loaded.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	try {
		const client = getOwnerSupabaseClient();
		await disconnectZoom(client);
		return json(await zoomStatus(client));
	} catch (error) {
		console.error('Could not disconnect Zoom.', error);
		return databaseError();
	}
};
