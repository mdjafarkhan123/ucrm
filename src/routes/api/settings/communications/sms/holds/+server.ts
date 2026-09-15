import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { safeSmsHold, type SmsHoldRow } from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

// The read-only holds and opt-out picture for the Phone & SMS settings page. Two facts, both bounded:
//   - Active outbound holds affecting this organization (its own holds plus any platform-wide hold). There are
//     only ever a few active holds, so they are returned in full; a contractor sees them but releases none here.
//   - The number of customers who have opted out. Per-customer opt-out evidence lives in Conversations and can
//     grow to the whole customer base, so the settings page shows a count only, not an unbounded list.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const client = getOwnerSupabaseClient();
	const organizationId = check.auth.organization.id;

	const holdsResult = await client
		.from('communication_sms_holds')
		.select('id, scope, reason, status, placed_at')
		.eq('status', 'active')
		.or(`scope.eq.platform,organization_id.eq.${organizationId}`)
		.order('placed_at', { ascending: false });

	if (holdsResult.error) {
		console.error('Could not load the SMS holds.', holdsResult.error);
		return json({ error: 'The holds could not be loaded.' }, { status: 500, headers: noStore });
	}

	const optOutResult = await client.rpc('communication_sms_opted_out_count', {
		p_organization_id: organizationId
	});

	if (optOutResult.error) {
		console.error('Could not count SMS opt-outs.', optOutResult.error);
		return json({ error: 'The holds could not be loaded.' }, { status: 500, headers: noStore });
	}

	return json(
		{
			holds: ((holdsResult.data ?? []) as SmsHoldRow[]).map(safeSmsHold),
			opt_outs: { total: optOutResult.data ?? 0 }
		},
		{ headers: noStore }
	);
};
