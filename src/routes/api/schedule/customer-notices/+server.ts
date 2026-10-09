import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { resolveAutomationAccess } from '$lib/server/access/automation';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError, PRIVATE_READ_HEADERS, unauthorized } from '$lib/server/api/errors';
import type { CustomerNoticeStatus } from '$lib/schedule/customer-notices';

// Client reminders Part 4: whether the "Notify customer" box belongs on a scheduling screen. It says only whether
// the booking confirmation and the "visit moved" email are on, so every member who can book may ask. Recipes are
// readable only to Automation viewers, so the owner client answers, scoped to this organization.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();
	const organizationId = auth.organization.id;

	const automation = await resolveAutomationAccess(
		event.locals.supabase,
		organizationId,
		auth.user.id
	);

	const { data, error } = await getOwnerSupabaseClient()
		.from('automation_recipes')
		.select('active_trigger_key')
		.eq('organization_id', organizationId)
		.eq('status', 'active')
		.in('active_trigger_key', ['appointment.booked', 'appointment.rescheduled']);
	if (error) return databaseError();

	const active = new Set<string>((data ?? []).map((row) => row.active_trigger_key));
	const running = automation.included && automation.authority_state === 'enabled';
	const result: CustomerNoticeStatus = {
		booked: running && active.has('appointment.booked'),
		rescheduled: running && active.has('appointment.rescheduled')
	};
	return json(result, { headers: PRIVATE_READ_HEADERS });
};
