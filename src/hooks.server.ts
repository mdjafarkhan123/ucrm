import { createServerClient } from '@supabase/ssr';
import type { Handle } from '@sveltejs/kit';
import { getPublicEnv } from '$lib/config/public';
import { getServerEnv } from '$lib/server/env';

const publicEnv = getPublicEnv();
getServerEnv();

export const handle: Handle = async ({ event, resolve }) => {
	event.locals.supabase = createServerClient(
		publicEnv.PUBLIC_SUPABASE_URL,
		publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY,
		{
			cookies: {
				getAll: () => event.cookies.getAll(),
				setAll: (cookiesToSet) => {
					cookiesToSet.forEach(({ name, value, options }) => {
						event.cookies.set(name, value, { ...options, path: '/' });
					});
				}
			}
		}
	);

	// Nothing runs between createServerClient and this call, per Supabase's SSR guide. This is the one
	// place the session gets rotated, and it has to happen before any route code so the refreshed cookie
	// is still writable. Leave it to the route and every query refreshes on its own instead, all racing
	// the same rotating refresh token until the auth server rate-limits them (429 over_request_rate_limit)
	// and the request quietly falls back to the `anon` role.
	const { data: claims } = await event.locals.supabase.auth.getClaims();

	// getClaims verifies the token in-process with WebCrypto against a cached JWKS -- this project signs
	// with ES256 -- so identity costs no round trip. getUser would cost one on every single request.
	// The trade-off is that a revoked user stays valid until their token expires; nothing here needs a
	// server-confirmed user record, only who is asking.
	event.locals.getUser = async () =>
		claims ? { id: claims.claims.sub, email: claims.claims.email ?? null } : null;

	return resolve(event);
};
