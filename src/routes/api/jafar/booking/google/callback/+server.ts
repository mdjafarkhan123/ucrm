import { redirect } from '@sveltejs/kit';
import { timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { connectGoogle } from '$lib/server/jafar/google';

// Jafar business management E5: where Google sends Jafar back. The code is swapped for tokens (kept encrypted), then
// he returns to Booking settings with the result in the address.

const querySchema = z.object({
	code: z.string().min(1).max(2000),
	state: z.string().min(1).max(200)
});

const back = (result: string) => `/jafar/settings/booking?google=${result}`;

function sameText(a: string, b: string) {
	const left = Buffer.from(a);
	const right = Buffer.from(b);
	return left.length === right.length && timingSafeEqual(left, right);
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const expected = event.cookies.get('google_oauth_state');
	event.cookies.delete('google_oauth_state', { path: '/api/jafar/booking/google' });

	const parsed = querySchema.safeParse(Object.fromEntries(event.url.searchParams));
	if (!parsed.success) redirect(303, back('declined'));
	if (!expected || !sameText(expected, parsed.data.state)) redirect(303, back('expired'));
	try {
		await connectGoogle(
			getOwnerSupabaseClient(),
			parsed.data.code,
			event.url.origin,
			session.email
		);
	} catch (error) {
		console.error('Could not connect Google.', error);
		redirect(303, back('failed'));
	}
	redirect(303, back('connected'));
};
