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
						try {
							event.cookies.set(name, value, { ...options, path: '/' });
						} catch (error) {
							if (!(error instanceof Error) || !error.message.includes('after the response has been generated')) {
								throw error;
							}
						}
					});
				}
			}
		}
	);

	let userPromise: ReturnType<typeof event.locals.supabase.auth.getUser> | undefined;
	event.locals.getUser = async () => {
		userPromise ??= event.locals.supabase.auth.getUser();
		const {
			data: { user }
		} = await userPromise;
		return user;
	};

	return resolve(event);
};
