import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsHoldPlacementSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-6: list one organization's outbound-SMS holds (active and released) for the Jafar Commercial
// access tab. Scoped to this organization's own 'organization'/'provider' holds only -- a platform-wide hold
// has no organization_id and is shown on the separate platform-wide surface (2C-5c), not repeated here.
// Read-only; holds are placed and released by the POST routes below and alongside.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: holds, error } = await client
			.from('communication_sms_holds')
			.select(
				'id, scope, reason, placed_by, placed_at, status, released_by, released_at, release_reason'
			)
			.eq('organization_id', parsedOrganizationId.data)
			.order('placed_at', { ascending: false });
		if (error) throw error;

		return json({ holds: holds ?? [] }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the SMS holds.', error);
		return json({ error: 'The SMS holds could not be loaded.' }, { status: 500 });
	}
};

// Stage 2C-5b: the platform owner places a reasoned outbound-SMS hold on one organization, at either the
// 'organization' scope (an ordinary business pause) or 'provider' scope (an emergency subaccount suspension).
// A platform-wide hold has no organization and is out of scope for this org-scoped route (deferred to 2C-5c,
// which also needs a platform-level audit target -- access_audit_events requires an organization_id).
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsHoldPlacementSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the hold.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{ error: 'Confirm your password before placing a hold.', step_up_required: true },
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_sms_place_hold', {
			p_scope: parsed.data.scope,
			p_organization_id: parsedOrganizationId.data,
			p_reason: parsed.data.reason,
			p_placed_by: PLATFORM_OWNER_ACTOR_ID
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type: 'communication_sms_hold_placed',
			target_type: 'communication_sms_hold',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ hold: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not place the SMS hold.', error);
		return json({ error: 'The hold could not be placed.' }, { status: 500 });
	}
};
