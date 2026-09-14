import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationSmsRetailRateSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

const noStore = { 'cache-control': 'no-store' };

// Stage 2C-5c (platform-scoped): the platform owner publishes a new SMS retail rate version. Rate versions
// are immutable (no update/delete, see 20260917100000) -- a change is always a new version, never a rewrite,
// so there is nothing to look up beforehand. Publishing a price list is routine (it moves no money immediately
// and only prices sends that happen later, the same treatment as a package change), so no step-up is required.
// The rate has no single owning organization, so its audit trail is platform_audit_events.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}

	const parsed = communicationSmsRetailRateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the rate.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_sms_set_retail_rate', {
			p_destination: parsed.data.destination,
			p_sender_type: parsed.data.sender_type,
			p_message_unit: parsed.data.message_unit,
			p_retail_rate_major: parsed.data.retail_rate_major,
			p_set_by: PLATFORM_OWNER_ACTOR_ID,
			p_currency_code: parsed.data.currency_code,
			p_provider_cost_major: parsed.data.provider_cost_major,
			p_effective_from: parsed.data.effective_from,
			p_note: parsed.data.note
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409, headers: noStore });
			}
			throw result.error;
		}

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'communication_sms_retail_rate_set',
			target_type: 'communication_sms_retail_rate',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ rate: result.data }, { headers: noStore });
	} catch (error) {
		console.error('Could not publish the SMS retail rate.', error);
		return json({ error: 'The rate could not be published.' }, { status: 500, headers: noStore });
	}
};
