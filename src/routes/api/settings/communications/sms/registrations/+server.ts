import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	SMS_REGISTRATION_COUNTRY_CODE,
	SMS_REGISTRATION_SENDER_TYPE,
	SMS_REGISTRATION_USE_CASE,
	safeSmsRegistration
} from '$lib/server/communications/sms-registration';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

function readinessFromRow(
	row: { readiness_state: string | null; live_sender_count: number } | null
) {
	return {
		readiness_state: row?.readiness_state ?? 'needs_setup',
		live_sender_count: row?.live_sender_count ?? 0
	};
}

// The organization's one A2-scope SMS registration (Stage 3B "Phone & SMS"). There is at most one row for the
// fixed (country, sender type, use case) key this launch uses, so the contractor page never has to pick from
// a list -- it reads null (not started) or the current registration with its plain readiness state.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const client = getOwnerSupabaseClient();
	const { data, error } = await client
		.from('communication_sms_registrations')
		.select(
			'id, country_code, sender_type, use_case, status, required_fixes, draft_questionnaire_version, draft_answers, draft_revision, draft_updated_at, submitted_at, updated_at'
		)
		.eq('organization_id', check.auth.organization.id)
		.eq('country_code', SMS_REGISTRATION_COUNTRY_CODE)
		.eq('sender_type', SMS_REGISTRATION_SENDER_TYPE)
		.eq('use_case', SMS_REGISTRATION_USE_CASE)
		.maybeSingle();

	if (error) {
		console.error('Could not load the SMS registration.', error);
		return json(
			{ error: 'The registration could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}

	const readinessResult = await client.rpc('communication_sms_readiness', {
		p_organization_id: check.auth.organization.id,
		p_country_code: SMS_REGISTRATION_COUNTRY_CODE,
		p_sender_type: SMS_REGISTRATION_SENDER_TYPE,
		p_use_case: SMS_REGISTRATION_USE_CASE
	});
	if (readinessResult.error) {
		console.error('Could not compute SMS readiness.', readinessResult.error);
		return json(
			{ error: 'The registration could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
	const readinessRow = Array.isArray(readinessResult.data)
		? readinessResult.data[0]
		: readinessResult.data;

	return json(
		{
			registration: data ? safeSmsRegistration(data) : null,
			readiness: {
				effective_mode: readinessRow?.effective_mode ?? 'off',
				...readinessFromRow(readinessRow)
			}
		},
		{ headers: noStore }
	);
};

// Start (or reopen) the organization's registration. Idempotent: a repeated call for an org that already has
// one just refreshes it and logs "info updated" rather than losing history (communication_sms_start_registration).
export const POST: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const result = await getOwnerSupabaseClient().rpc('communication_sms_start_registration', {
		p_organization_id: check.auth.organization.id,
		p_country_code: SMS_REGISTRATION_COUNTRY_CODE,
		p_sender_type: SMS_REGISTRATION_SENDER_TYPE,
		p_use_case: SMS_REGISTRATION_USE_CASE,
		p_actor: check.auth.user.id
	});

	if (result.error) {
		console.error('Could not start the SMS registration.', result.error);
		return json(
			{ error: 'The registration could not be started.' },
			{ status: 500, headers: noStore }
		);
	}

	return json({ registration: safeSmsRegistration(result.data) }, { headers: noStore });
};
