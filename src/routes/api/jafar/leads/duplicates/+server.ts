import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { leadDuplicateCheckSchema } from '$lib/server/validation/lead.schema';
import type { LeadDuplicate } from '$lib/jafar/leads';

// Jafar business management B1: while a Lead is being added or edited, the Leads, Applications and Organizations that look
// like the same business -- same website, email, phone, or name. Shown for review; nothing is merged or blocked.
// A POST so email addresses and phone numbers stay out of URLs and logs; it changes nothing.

export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadDuplicateCheckSchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'The duplicate check is invalid.' });

	const input = parsed.data;
	const emails = input.emails.filter(Boolean);
	const phones = input.phones.filter(Boolean);
	// Nothing to compare yet: answer without asking the database.
	if (!input.business_name && !input.website && !emails.length && !phones.length)
		return json({ duplicates: [] }, { headers: NO_STORE_HEADERS });

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_possible_duplicates', {
			business_name: input.business_name || undefined,
			country_code: input.country_code || undefined,
			website: input.website || undefined,
			emails,
			phones,
			exclude_id: input.exclude_id
		});
		if (error) throw error;
		return json(
			{ duplicates: (data ?? []) as unknown as LeadDuplicate[] },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not check for duplicate Leads.', error);
		return json({ error: 'The duplicate check is unavailable.' }, { status: 500 });
	}
};
