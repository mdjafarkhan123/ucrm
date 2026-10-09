import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { LEAD_NOT_FOUND } from '$lib/server/jafar/lead-approval';

// Jafar business management E2: a Lead's booking requests still waiting for an answer (approval mode). Anyone who
// can open Leads sees them; answering needs Leads & Deals change access (the gate checks the POST).

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_booking_requests', {
		target_relationship_id: event.params.id
	});
	if (error) {
		console.error('Could not load the booking requests.', error);
		return json({ error: 'Booking requests could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: PRIVATE_READ_HEADERS });
};
