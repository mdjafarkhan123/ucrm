import { randomBytes } from 'node:crypto';
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { zoomAuthorizeUrl, zoomConfigured } from '$lib/server/jafar/zoom';

// Jafar business management E4b: sends Jafar to Zoom's own sign-in page. The random state, kept in a cookie only
// this browser holds, is checked when Zoom sends him back, so nobody else can finish his sign-in.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!zoomConfigured()) redirect(303, '/jafar/settings/booking?zoom=not_set_up');
	const state = randomBytes(24).toString('base64url');
	event.cookies.set('zoom_oauth_state', state, {
		path: '/api/jafar/booking/zoom',
		httpOnly: true,
		sameSite: 'lax',
		secure: event.url.protocol === 'https:',
		maxAge: 600
	});
	redirect(303, zoomAuthorizeUrl(event.url.origin, state));
};
