import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';

export const load: PageServerLoad = (event) => {
	if (getOwnerSession(event)) throw redirect(303, '/jafar');
};
