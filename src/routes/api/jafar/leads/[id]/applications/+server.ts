import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	leadApplicationLinkSchema,
	leadApplicationSearchSchema
} from '$lib/server/validation/lead.schema';
import type { ApplicationCandidate } from '$lib/jafar/lead-history';
import { linkResultResponse } from '$lib/server/jafar/lead-history';

// Jafar business management B2: Applications to offer in the Lead page's picker, and linking one to this Lead.
// An Application belongs to one business at most; one already linked elsewhere is refused, never moved.

const LEAD_NOT_FOUND = 'This Lead no longer exists.';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const parsed = leadApplicationSearchSchema.safeParse({
		search: event.url.searchParams.get('search') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The search is too long.' }, { status: 422 });

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc(
			'owner_lead_application_candidates',
			{
				target_id: event.params.id,
				search_term: parsed.data.search || undefined
			}
		);
		if (error) throw error;
		// Contact details of people who applied: kept out of any cache but the page's own.
		return json(
			{ applications: (data ?? []) as unknown as ApplicationCandidate[] },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not search Applications for a Lead.', error);
		return json({ error: 'Applications could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadApplicationLinkSchema.safeParse(body);
	if (!parsed.success) return validationError({ application_id: 'Choose an Application.' });

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_link_application', {
			actor_email: session.email,
			target_id: event.params.id,
			target_application_id: parsed.data.application_id,
			target_link: true
		});
		if (error) throw error;
		return linkResultResponse(data);
	} catch (error) {
		console.error('Could not link the Application.', error);
		return databaseError();
	}
};
