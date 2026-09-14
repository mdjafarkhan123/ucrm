import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsRegistrationStartSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-5c: the platform owner starts (or reopens) a registration for one organization's country,
// sender type and use case. Carrier submission is a routine action (docs/jafar-organization-management-
// mission.md "High-impact action security"), so no step-up is required -- a reason/confirmation only.
// The command itself is idempotent: calling it again for the same key updates the existing row and logs
// 'info_updated' instead of losing history, so this route always records the audit event it produced.
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

	const parsed = communicationSmsRegistrationStartSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the registration.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_sms_start_registration', {
			p_organization_id: parsedOrganizationId.data,
			p_country_code: parsed.data.country_code,
			p_sender_type: parsed.data.sender_type,
			p_use_case: parsed.data.use_case,
			p_actor: PLATFORM_OWNER_ACTOR_ID
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
			event_type: 'communication_sms_registration_started',
			target_type: 'communication_sms_registration',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ registration: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not start the SMS registration.', error);
		return json({ error: 'The registration could not be started.' }, { status: 500 });
	}
};
