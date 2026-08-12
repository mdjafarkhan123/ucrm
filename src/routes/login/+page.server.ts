import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	if (await event.locals.getUser()) throw redirect(303, '/dashboard');
};
