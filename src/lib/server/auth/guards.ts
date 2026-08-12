import { redirect, type RequestEvent } from '@sveltejs/kit';

export async function requireContractor(event: RequestEvent) {
	const user = await event.locals.getUser();
	if (!user) throw redirect(303, '/login');
	return user;
}
