import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsRegistrationOutcomeSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-5c: the platform owner records the carrier/provider decision on a registration under review --
// approved with the safe outcome text, or action_needed with the safe fixes the contractor must correct.
// Recording a decision is routine (not on the step-up list): a reason/confirmation only.
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

	const parsed = communicationSmsRegistrationOutcomeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the outcome.', field_errors: zodOwnerFieldErrors(parsed.error) },
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

		const result = await client.rpc('communication_sms_record_registration_outcome', {
			p_registration_id: parsedRegistrationId.data,
			p_status: parsed.data.status,
			p_decided_by: PLATFORM_OWNER_ACTOR_ID,
			p_provider_outcome:
				parsed.data.status === 'approved' ? parsed.data.provider_outcome : undefined,
			p_required_fixes:
				parsed.data.status === 'action_needed' ? parsed.data.required_fixes : undefined
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
			event_type: 'communication_sms_registration_decided',
			target_type: 'communication_sms_registration',
			target_key: parsedRegistrationId.data,
			before_state: { status: existing.status },
			after_state: result.data
		});

		return json({ registration: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not record the SMS registration outcome.', error);
		return json({ error: 'The registration outcome could not be recorded.' }, { status: 500 });
	}
};
