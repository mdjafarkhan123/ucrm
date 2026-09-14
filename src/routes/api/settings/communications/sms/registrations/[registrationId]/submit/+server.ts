import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	SMS_REGISTRATION_ATTESTATION_TEXT,
	SMS_REGISTRATION_ATTESTATION_VERSION
} from '$lib/server/communications/sms-registration';
import {
	smsRegistrationFieldErrors,
	smsRegistrationSubmitSchema
} from '$lib/server/validation/communications-sms-registration.schema';

const noStore = { 'Cache-Control': 'no-store' };
const registrationIdSchema = z.string().uuid();

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const registrationId = registrationIdSchema.safeParse(event.params.registrationId);
	if (!registrationId.success) {
		return json(
			{ error: 'The registration identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = smsRegistrationSubmitSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please complete the registration before submitting.',
				field_errors: smsRegistrationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const attestorEmail = check.auth.user.email;
	if (!attestorEmail) {
		return json(
			{
				error:
					'Your signed-in account needs an email address before it can attest this registration.'
			},
			{ status: 409, headers: noStore }
		);
	}

	const result = await getOwnerSupabaseClient().rpc(
		'communication_sms_submit_registration_answers',
		{
			p_organization_id: check.auth.organization.id,
			p_registration_id: registrationId.data,
			p_expected_revision: parsed.data.expected_revision,
			p_questionnaire_version: parsed.data.questionnaire_version,
			p_answers: parsed.data.answers,
			p_attestation_version: SMS_REGISTRATION_ATTESTATION_VERSION,
			p_attestation_text: SMS_REGISTRATION_ATTESTATION_TEXT,
			p_attested_by: check.auth.user.id,
			p_attestor_email: attestorEmail
		}
	);
	if (result.error) {
		if (result.error.code === 'P0001') {
			const conflict = result.error.details?.includes('revision_conflict');
			return json(
				{
					error: conflict
						? 'Someone else changed this registration. Reload it and try again.'
						: result.error.message,
					reason: conflict ? 'revision_conflict' : 'registration_conflict'
				},
				{ status: 409, headers: noStore }
			);
		}
		console.error('Could not submit the SMS registration.', result.error);
		return json(
			{ error: 'The registration could not be submitted.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(
		{
			registration: {
				id: result.data.id,
				status: result.data.status,
				submitted_at: result.data.submitted_at,
				draft_revision: result.data.draft_revision
			}
		},
		{ headers: noStore }
	);
};
