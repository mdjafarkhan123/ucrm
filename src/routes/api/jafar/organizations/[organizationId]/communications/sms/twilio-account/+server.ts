import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

// Stage 10 Part 5b-2: the Twilio account Uplift made for one organization, for the Twilio account side card on
// its Communications › Texting view. Read-only; `null` until Uplift makes the account.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: account, error } = await client
			.from('communication_twilio_accounts')
			.select('subaccount_sid, messaging_service_sid, lifecycle_state, created_at')
			.eq('organization_id', parsedOrganizationId.data)
			.maybeSingle();
		if (error) throw error;

		return json({ account: account ?? null }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the Twilio account.', error);
		return json({ error: 'The Twilio account could not be loaded.' }, { status: 500 });
	}
};
