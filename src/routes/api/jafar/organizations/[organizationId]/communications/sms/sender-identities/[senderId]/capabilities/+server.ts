import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsSenderCapabilitiesSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

// Stage 2C-5c: the platform owner records the safe provider capabilities (country, sender type, SMS/MMS/
// Voice) of one assigned business number, and optionally links the registration it belongs to. Recording
// provider-reported facts is routine (no step-up). The registration, if given, must belong to the same
// organization -- enforced by the database's own composite foreign key, surfaced here as a clean 404.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedSenderId = organizationIdSchema.safeParse(event.params.senderId);
	if (!parsedOrganizationId.success || !parsedSenderId.success) {
		return json({ error: 'The sender identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsSenderCapabilitiesSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the capabilities.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await client
			.from('communication_sms_sender_identities')
			.select('id, organization_id, capable_sms, capable_mms, capable_voice, registration_id')
			.eq('id', parsedSenderId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing || existing.organization_id !== parsedOrganizationId.data) {
			return json({ error: 'That sender was not found.' }, { status: 404 });
		}

		const result = await client.rpc('communication_sms_set_sender_capabilities', {
			p_sender_identity_id: parsedSenderId.data,
			p_country_code: parsed.data.country_code,
			p_sender_type: parsed.data.sender_type,
			p_capable_sms: parsed.data.capable_sms,
			p_capable_mms: parsed.data.capable_mms,
			p_capable_voice: parsed.data.capable_voice,
			p_registration_id: parsed.data.registration_id
		});

		if (result.error) {
			if (result.error.code === '23503') {
				return json(
					{ error: 'That registration was not found for this organization.' },
					{ status: 404 }
				);
			}
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type: 'communication_sms_sender_capabilities_set',
			target_type: 'communication_sms_sender_identity',
			target_key: parsedSenderId.data,
			before_state: {
				capable_sms: existing.capable_sms,
				capable_mms: existing.capable_mms,
				capable_voice: existing.capable_voice,
				registration_id: existing.registration_id
			},
			after_state: result.data
		});

		return json({ sender: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not set the SMS sender capabilities.', error);
		return json({ error: 'The sender capabilities could not be set.' }, { status: 500 });
	}
};
