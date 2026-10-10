import { randomBytes } from 'node:crypto';
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { googleAuthorizeUrl, googleConfigured } from '$lib/server/jafar/google';

// Jafar business management E5: sends Jafar to Google's own sign-in page. The random state, kept in a cookie only
// this browser holds, is checked when Google sends him back, so nobody else can finish his sign-in.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!googleConfigured()) redirect(303, '/jafar/settings/booking?google=not_set_up');
	const state = randomBytes(24).toString('base64url');
	event.cookies.set('google_oauth_state', state, {
		path: '/api/jafar/booking/google',
		httpOnly: true,
		sameSite: 'lax',
		secure: event.url.protocol === 'https:',
		maxAge: 600
	});
	redirect(303, googleAuthorizeUrl(event.url.origin, state));
};
