import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsRegistrationCheckSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-5c: the platform owner records that real provider readiness was checked, without changing the
// registration's status -- purely informational, so it carries no reason requirement and is routine (no
// step-up). Refreshes last_checked_at so the page can show when readiness was last confirmed.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedRegistrationId = organizationIdSchema.safeParse(event.params.registrationId);
	if (!parsedOrganizationId.success || !parsedRegistrationId.success) {
		return json({ error: 'The registration identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsRegistrationCheckSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the check.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await client
			.from('communication_sms_registrations')
			.select('id, organization_id, status')
			.eq('id', parsedRegistrationId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing || existing.organization_id !== parsedOrganizationId.data) {
			return json({ error: 'That registration was not found.' }, { status: 404 });
		}

		const result = await client.rpc('communication_sms_record_registration_check', {
			p_registration_id: parsedRegistrationId.data,
			p_checked_by: PLATFORM_OWNER_ACTOR_ID,
			p_detail: parsed.data.detail
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
			event_type: 'communication_sms_registration_check_recorded',
			target_type: 'communication_sms_registration',
			target_key: parsedRegistrationId.data,
			before_state: { status: existing.status },
			after_state: result.data
		});

		return json({ registration: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not record the SMS registration check.', error);
		return json({ error: 'The registration check could not be recorded.' }, { status: 500 });
	}
};
