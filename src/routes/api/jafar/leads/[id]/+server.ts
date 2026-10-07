import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { presentHistory, type RawHistoryPage } from '$lib/server/jafar/lead-history';
import { leadChangeSchema } from '$lib/server/validation/lead.schema';
import type { LeadPage } from '$lib/jafar/lead-history';
import { canUseJafarPath } from '$lib/jafar/team-access';
import type { BusinessDeal } from '$lib/jafar/deals';

// Jafar business management B2: one Lead's page in one request, and changing its status or next action. Each
// change is written to the Lead's history in the same database transaction.

const LEAD_NOT_FOUND = 'This Lead no longer exists.';

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	try {
		// B4: the business's Deals are read alongside, in the same request.
		const client = getOwnerSupabaseClient();
		const [{ data, error }, deals] = await Promise.all([
			client.rpc('owner_lead_page', { target_id: event.params.id }),
			client.rpc('owner_business_deals', { target_relationship_id: event.params.id })
		]);
		if (error) throw error;
		if (deals.error) throw deals.error;
		if (!data) return notFound(LEAD_NOT_FOUND);

		const page = data as unknown as Omit<LeadPage, 'history' | 'deals'> & {
			history: RawHistoryPage;
		};
		// Linked Applications carry their contact's details: only for someone who can open Applications.
		const applications = canUseJafarPath(session, '/api/jafar/prospects') ? page.applications : [];
		return json(
			{
				...page,
				applications,
				deals: deals.data as unknown as BusinessDeal[],
				history: presentHistory(page.history)
			} satisfies LeadPage,
			{
				headers: PRIVATE_READ_HEADERS
			}
		);
	} catch (error) {
		console.error('Could not load the Lead.', error);
		return json({ error: 'This Lead could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadChangeSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return validationError(fieldErrors);
	}

	const change = parsed.data;
	const next = change.next_action;
	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_change', {
			actor_email: session.email,
			target_id: event.params.id,
			target_status: change.lead_status,
			next_action_mode: next?.mode ?? 'keep',
			target_next_action: next && next.mode !== 'clear' ? (next.text ?? undefined) : undefined,
			target_due_on: next && next.mode !== 'clear' ? (next.due_on ?? undefined) : undefined
		});
		if (error) {
			// The database's own refusals (e.g. "There is no next action to mark done.") are already in plain words.
			if (error.code === '22023') return validationError({ form: error.message }, 409);
			throw error;
		}
		if (!data) return notFound(LEAD_NOT_FOUND);
		return json({ ok: true });
	} catch (error) {
		console.error('Could not change the Lead.', error);
		return databaseError();
	}
};
