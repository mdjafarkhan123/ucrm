import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { resolveAutomationAccess } from '$lib/server/access/automation';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError, PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { MESSAGE_SWITCH_TRIGGERS, type MessageAutomationStatus } from '$lib/clients/api';

// Client reminders Part 3: which client Communication settings switches really send right now. A switch only
// sends while its business-wide automation is on (docs/client-reminders-behavior-contract.md § Customer messages:
// shared rules), so the client screen can say "Not sending" instead of promising a message that never goes out.
// Anyone who can see clients may read this; it says only whether each reminder is on, never how it is set up.
export const GET: RequestHandler = async (event) => {
	const check = await requireClientPermission(event, 'customers.view');
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;

	const automation = await resolveAutomationAccess(
		event.locals.supabase,
		organizationId,
		check.auth.user.id,
		check.access
	);

	// Recipes are readable only to Automation viewers; the owner client answers the one yes/no question for
	// everyone else, scoped to this organization.
	const { data, error } = await getOwnerSupabaseClient()
		.from('automation_recipes')
		.select('active_trigger_key')
		.eq('organization_id', organizationId)
		.eq('status', 'active')
		.in('active_trigger_key', Object.values(MESSAGE_SWITCH_TRIGGERS));
	if (error) return databaseError();

	const activeTriggers = new Set((data ?? []).map((row) => row.active_trigger_key));
	const running = automation.included && automation.authority_state === 'enabled';
	const sending = Object.fromEntries(
		Object.entries(MESSAGE_SWITCH_TRIGGERS).map(([flag, trigger]) => [
			flag,
			running && activeTriggers.has(trigger)
		])
	) as MessageAutomationStatus['sending'];

	const result: MessageAutomationStatus = { sending, can_manage: automation.can_manage };
	return json(result, { headers: PRIVATE_READ_HEADERS });
};
