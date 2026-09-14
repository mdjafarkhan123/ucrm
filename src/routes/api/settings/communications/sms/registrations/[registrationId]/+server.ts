import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { safeSmsRegistration } from '$lib/server/communications/sms-registration';
import {
	smsRegistrationDraftSaveSchema,
	smsRegistrationFieldErrors
} from '$lib/server/validation/communications-sms-registration.schema';

const noStore = { 'Cache-Control': 'no-store' };
const registrationIdSchema = z.string().uuid();

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const registrationId = registrationIdSchema.safeParse(event.params.registrationId);
	if (!registrationId.success) {
		return json(
			{ error: 'The registration identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_registrations')
		.select(
			'id, country_code, sender_type, use_case, status, required_fixes, draft_questionnaire_version, draft_answers, draft_revision, draft_updated_at, submitted_at, updated_at'
		)
		.eq('organization_id', check.auth.organization.id)
		.eq('id', registrationId.data)
		.maybeSingle();

	if (error) {
		console.error('Could not load the SMS registration draft.', error);
		return json(
			{ error: 'The registration could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
	if (!data)
		return json({ error: 'The registration was not found.' }, { status: 404, headers: noStore });

	return json({ registration: safeSmsRegistration(data) }, { headers: noStore });
};

export const PATCH: RequestHandler = async (event) => {
	const check = await authorize(event);
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
	const parsed = smsRegistrationDraftSaveSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the registration details.',
				field_errors: smsRegistrationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const result = await getOwnerSupabaseClient().rpc('communication_sms_save_registration_draft', {
		p_organization_id: check.auth.organization.id,
		p_registration_id: registrationId.data,
		p_expected_revision: parsed.data.expected_revision,
		p_questionnaire_version: parsed.data.questionnaire_version,
		p_answers: parsed.data.answers,
		p_actor: check.auth.user.id
	});
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
		console.error('Could not save the SMS registration draft.', result.error);
		return json(
			{ error: 'The registration could not be saved.' },
			{ status: 500, headers: noStore }
		);
	}

	return json({ registration: safeSmsRegistration(result.data) }, { headers: noStore });
};
