import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The Send SMS action editor's optional "pin a number" picker: only numbers eligible to send right now. Read
// under Automation's own access gate (`view` is enough — this is a picker, not a write) rather than
// Communications' `conversations.manage_connections`, so an automation editor without a separate connections
// permission still sees the choice; the send effect re-checks eligibility live regardless of what is shown
// here. A contractor has only a handful of numbers, so the list is returned unpaged.
export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_sender_identities')
		.select('id, phone_number, display_name, is_default_sender')
		.eq('organization_id', check.auth.organization.id)
		.eq('lifecycle_state', 'ready')
		.eq('capable_sms', true)
		.order('is_default_sender', { ascending: false })
		.order('phone_number', { ascending: true });

	if (error) {
		console.error('Could not load the automation SMS senders.', error);
		return databaseError();
	}

	return json(
		{
			senders: (data ?? []).map((row) => ({
				id: row.id,
				phone_number: row.phone_number,
				display_name: row.display_name,
				is_default_sender: row.is_default_sender
			}))
		},
		{ headers: NO_STORE_HEADERS }
	);
};
