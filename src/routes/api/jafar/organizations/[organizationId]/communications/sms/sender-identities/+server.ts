import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

// Stage 2C-6: list one organization's SMS sender identities (assigned business numbers) and their
// provider-reported capabilities, for the Jafar Integrations tab. Read-only; capabilities are set at
// sender-identities/[senderId]/capabilities.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: senders, error } = await client
			.from('communication_sms_sender_identities')
			.select(
				'id, phone_number, display_name, lifecycle_state, allows_manual, allows_automated, country_code, sender_type, capable_sms, capable_mms, capable_voice, registration_id, created_at, updated_at'
			)
			.eq('organization_id', parsedOrganizationId.data)
			.order('created_at');
		if (error) throw error;

		return json({ senders: senders ?? [] }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the SMS sender identities.', error);
		return json({ error: 'SMS sender identities could not be loaded.' }, { status: 500 });
	}
};
