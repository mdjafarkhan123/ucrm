import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

// Stage 10 Part 5b: the countries one business asked to text, for its Communications › Texting view, with the
// Twilio account a country's "See it in Twilio" opens. Read-only.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc(
			'communication_sms_organization_destinations',
			{ p_organization_id: parsedOrganizationId.data }
		);
		if (error) throw error;
		return json(data, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the texting countries.', error);
		return json({ error: 'The countries could not be loaded.' }, { status: 500 });
	}
};
