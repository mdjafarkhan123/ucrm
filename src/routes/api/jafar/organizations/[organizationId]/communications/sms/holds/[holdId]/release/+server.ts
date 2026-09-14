import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsHoldReleaseSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-5b: release an active hold on this organization. The release command itself is not organization-
// scoped, so we look the hold up first and confirm it belongs to this organization before releasing it --
// the same pattern the 2C-5a credit top-up decision uses, so a mismatched id is a clean 404.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedHoldId = organizationIdSchema.safeParse(event.params.holdId);
	if (!parsedOrganizationId.success || !parsedHoldId.success) {
		return json({ error: 'The hold identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsHoldReleaseSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the release.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{ error: 'Confirm your password before releasing a hold.', step_up_required: true },
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await client
			.from('communication_sms_holds')
			.select('id, organization_id, status')
			.eq('id', parsedHoldId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing || existing.organization_id !== parsedOrganizationId.data) {
			return json({ error: 'That hold was not found.' }, { status: 404 });
		}

		const result = await client.rpc('communication_sms_release_hold', {
			p_hold_id: parsedHoldId.data,
			p_released_by: PLATFORM_OWNER_ACTOR_ID,
			p_release_reason: parsed.data.release_reason
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
			event_type: 'communication_sms_hold_released',
			target_type: 'communication_sms_hold',
			target_key: parsedHoldId.data,
			before_state: { status: existing.status },
			after_state: result.data
		});

		return json({ hold: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not release the SMS hold.', error);
		return json({ error: 'The hold could not be released.' }, { status: 500 });
	}
};
