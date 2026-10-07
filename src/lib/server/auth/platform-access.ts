import { json, redirect, type RequestEvent } from '@sveltejs/kit';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { canUseJafarPath, teammateHomePath } from '$lib/jafar/team-access';

/**
 * The few `/jafar` addresses a visitor reaches before signing in. Each one is safe without a session:
 * the sign-in page and the sign-in/sign-out endpoint create or end one, and a teammate's invitation and
 * password-reset pages and endpoints act only on the secret single-use link they carry (ADR 0008).
 */
const OPEN_PATHS = new Set([
	'/jafar/login',
	'/api/jafar/session',
	'/jafar/join',
	'/jafar/forgot-password',
	'/jafar/reset-password',
	'/api/jafar/account/join',
	'/api/jafar/account/password-reset',
	'/api/jafar/account/password-reset/complete'
]);

/**
 * Scheduled jobs the database calls with a shared secret instead of a browser session. Every route here
 * checks its own bearer secret and refuses everyone else.
 */
const SECRET_AUTHENTICATED_PREFIX = '/api/jafar/internal/';

export function isJafarPath(pathname: string) {
	return (
		pathname === '/jafar' ||
		pathname.startsWith('/jafar/') ||
		pathname === '/api/jafar' ||
		pathname.startsWith('/api/jafar/')
	);
}

export function isOpenJafarPath(pathname: string) {
	return OPEN_PATHS.has(pathname) || pathname.startsWith(SECRET_AUTHENTICATED_PREFIX);
}

/**
 * The one "who is this and what may they do" gate for the whole Jafar Panel. It runs at the front door
 * for every `/jafar` page and `/api/jafar` request, before any route code, so a page or endpoint that
 * forgets its own check is still closed -- and a page's server load is never relied on to be protected by
 * its layout, which SvelteKit does not always re-run on client navigation. The platform owner passes
 * everything; a teammate passes only their role's areas (`$lib/jafar/team-access`).
 *
 * Returns null when the request may continue, or the refusal to send: 401 without a session and 403
 * outside a teammate's areas for the API; for pages, a redirect to sign-in or to the teammate's own home.
 */
export async function guardJafarRequest(event: RequestEvent): Promise<Response | null> {
	const { pathname } = event.url;
	if (!isJafarPath(pathname) || isOpenJafarPath(pathname)) return null;

	const isApi = pathname === '/api/jafar' || pathname.startsWith('/api/jafar/');
	const session = await getOwnerSession(event);
	if (!session) {
		if (isApi) return ownerUnauthorized();
		redirect(303, '/jafar/login');
	}

	if (canUseJafarPath(session, pathname, event.request.method)) return null;

	if (isApi) {
		return json({ error: 'Your access does not include this action.' }, { status: 403 });
	}
	redirect(303, teammateHomePath({ role: session.role!, access: session.access }));
}
