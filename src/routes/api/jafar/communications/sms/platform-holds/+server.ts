import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationSmsPlatformHoldPlacementSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

const noStore = { 'cache-control': 'no-store' };

// Stage 2C-5c (platform-scoped): the platform owner pauses outbound SMS for every organization at once, an
// emergency control (docs/jafar-organization-management-mission.md "High-impact action security" --
// "platform-wide emergency controls"), so it requires step-up. A platform hold names no organization, so its
// audit trail is platform_audit_events, not access_audit_events (which requires one).
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}

	const parsed = communicationSmsPlatformHoldPlacementSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the hold.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before pausing texting platform-wide.',
				step_up_required: true
			},
			{ status: 403, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		// Postgres cannot express argument nullability, so the generated Args type reads
		// p_organization_id as required. Null is what "no organization -- platform scope" means here.
		const result = await client.rpc('communication_sms_place_hold', {
			p_scope: 'platform',
			p_organization_id: null,
			p_reason: parsed.data.reason,
			p_placed_by: PLATFORM_OWNER_ACTOR_ID
		} as never);

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409, headers: noStore });
			}
			throw result.error;
		}

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'communication_sms_platform_hold_placed',
			target_type: 'communication_sms_hold',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ hold: result.data }, { headers: noStore });
	} catch (error) {
		console.error('Could not place the platform-wide SMS hold.', error);
		return json({ error: 'The hold could not be placed.' }, { status: 500, headers: noStore });
	}
};
