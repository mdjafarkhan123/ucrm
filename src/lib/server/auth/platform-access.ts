import { redirect, type RequestEvent } from '@sveltejs/kit';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';

/**
 * The few `/jafar` addresses a visitor reaches before signing in. Each one is safe without a session:
 * the sign-in page and the sign-in/sign-out endpoint create or end one.
 */
const OPEN_PATHS = new Set(['/jafar/login', '/api/jafar/session']);

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
 * its layout, which SvelteKit does not always re-run on client navigation. Today the only person who can
 * pass is the configured platform owner, with full access; teammates and their areas arrive in stage D.
 *
 * Returns null when the request may continue, or the refusal to send: 401 for the API, a redirect to
 * sign-in for pages.
 */
export async function guardJafarRequest(event: RequestEvent): Promise<Response | null> {
	const { pathname } = event.url;
	if (!isJafarPath(pathname) || isOpenJafarPath(pathname)) return null;

	if (await getOwnerSession(event)) return null;

	if (pathname === '/api/jafar' || pathname.startsWith('/api/jafar/')) return ownerUnauthorized();
	redirect(303, '/jafar/login');
}
