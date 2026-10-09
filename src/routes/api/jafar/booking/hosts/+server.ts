import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { hostChoices } from '$lib/server/jafar/booking-hosts';

// Jafar business management E3: the teammates a meeting type can name as hosts. Jafar is always one too.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		return json(
			{ choices: await hostChoices(getOwnerSupabaseClient()) },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not list who can host a call.', error);
		return json({ error: 'Your team could not be loaded.' }, { status: 500 });
	}
};
