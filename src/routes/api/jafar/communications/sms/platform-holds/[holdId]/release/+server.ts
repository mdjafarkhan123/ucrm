import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsHoldReleaseSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

const noStore = { 'cache-control': 'no-store' };

// Stage 2C-5c (platform-scoped): release an active platform-wide hold. Same emergency-control step-up as
// placing one. The release command is not scope-specific, so we look the hold up first and confirm it is
// actually a platform hold before releasing it -- the same pattern the org-scoped release route uses to keep
// a mismatched id a clean 404 rather than silently releasing the wrong hold.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedHoldId = organizationIdSchema.safeParse(event.params.holdId);
	if (!parsedHoldId.success) {
		return json({ error: 'The hold identifier is invalid.' }, { status: 422, headers: noStore });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}

	const parsed = communicationSmsHoldReleaseSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the release.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before releasing a platform-wide hold.',
				step_up_required: true
			},
			{ status: 403, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await client
			.from('communication_sms_holds')
			.select('id, scope, status')
			.eq('id', parsedHoldId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing || existing.scope !== 'platform') {
			return json({ error: 'That hold was not found.' }, { status: 404, headers: noStore });
		}

		const result = await client.rpc('communication_sms_release_hold', {
			p_hold_id: parsedHoldId.data,
			p_released_by: PLATFORM_OWNER_ACTOR_ID,
			p_release_reason: parsed.data.release_reason
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409, headers: noStore });
			}
			throw result.error;
		}

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'communication_sms_platform_hold_released',
			target_type: 'communication_sms_hold',
			target_key: parsedHoldId.data,
			before_state: { status: existing.status },
			after_state: result.data
		});

		return json({ hold: result.data }, { headers: noStore });
	} catch (error) {
		console.error('Could not release the platform-wide SMS hold.', error);
		return json({ error: 'The hold could not be released.' }, { status: 500, headers: noStore });
	}
};
