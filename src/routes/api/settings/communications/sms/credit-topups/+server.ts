import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	smsCreditTopupRequestSchema,
	smsSettingsFieldErrors
} from '$lib/server/validation/communications-sms-settings.schema';
import {
	safeSmsCreditTopupRequest,
	type SmsCreditTopupRequestRow
} from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

const TOPUP_COLUMNS =
	'id, requested_amount_minor, currency_code, offsite_reference, note, status, requested_at, decided_at, decision_reason, settled_amount_minor';

// Stage 3D: the contractor's own SMS credit top-up requests. Submitting one (communication_sms_request_credit_topup)
// creates no spendable credit -- it is worth nothing until Jafar confirms the money actually arrived
// (Jafar-only, src/routes/api/jafar/.../credit-topups). This route only lists and creates the organization's own
// requests, never decides one.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_credit_topup_requests')
		.select(TOPUP_COLUMNS)
		.eq('organization_id', check.auth.organization.id)
		.order('requested_at', { ascending: false });

	if (error) {
		console.error('Could not load the SMS credit top-up requests.', error);
		return json(
			{ error: 'The top-up requests could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(
		{ requests: ((data ?? []) as SmsCreditTopupRequestRow[]).map(safeSmsCreditTopupRequest) },
		{ headers: noStore }
	);
};

export const POST: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = smsCreditTopupRequestSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the top-up request.',
				field_errors: smsSettingsFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const result = await getOwnerSupabaseClient().rpc('communication_sms_request_credit_topup', {
		p_organization_id: check.auth.organization.id,
		p_requested_by: check.auth.user.id,
		p_requested_amount_minor: parsed.data.requested_amount_minor,
		p_offsite_reference: parsed.data.offsite_reference ?? undefined,
		p_note: parsed.data.note ?? undefined
	});

	if (result.error) {
		console.error('Could not submit the SMS credit top-up request.', result.error);
		return json(
			{ error: 'The top-up request could not be submitted.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(
		{ request: safeSmsCreditTopupRequest(result.data as SmsCreditTopupRequestRow) },
		{ status: 201, headers: noStore }
	);
};
