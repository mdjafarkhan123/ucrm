import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { safeSmsSender, type SmsSenderRow } from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

// The organization's SMS numbers for the Phone & SMS settings page. Contractors read this list to name a number
// or pick their default; buying and releasing numbers stay owner/provider actions and never appear as writes here.
// A contractor has only a handful of numbers, so the full (organization-scoped) list is returned unpaged.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_sender_identities')
		.select(
			'id, phone_number, display_name, country_code, sender_type, lifecycle_state, capable_sms, capable_mms, capable_voice, allows_manual, allows_automated, registration_id, is_default_sender'
		)
		.eq('organization_id', check.auth.organization.id)
		.neq('lifecycle_state', 'released')
		.order('is_default_sender', { ascending: false })
		.order('phone_number', { ascending: true });

	if (error) {
		console.error('Could not load the SMS numbers.', error);
		return json({ error: 'The numbers could not be loaded.' }, { status: 500, headers: noStore });
	}

	return json(
		{ numbers: ((data ?? []) as SmsSenderRow[]).map(safeSmsSender) },
		{ headers: noStore }
	);
};
