import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	smsComplianceSchema,
	smsSettingsFieldErrors
} from '$lib/server/validation/communications-sms-settings.schema';
import { safeSmsCompliance, type SmsComplianceRow } from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

// The organization's SMS compliance preferences (opt-out language, sender identification and re-insertion
// interval). A missing row means the organization is on the system defaults, which is what the GET returns.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_compliance_settings')
		.select(
			'opt_out_enabled, opt_out_text, sender_info_enabled, sender_info_text, periodic_reinsert_days, updated_at'
		)
		.eq('organization_id', check.auth.organization.id)
		.maybeSingle();

	if (error) {
		console.error('Could not load the SMS compliance settings.', error);
		return json(
			{ error: 'The compliance settings could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(
		{ compliance: safeSmsCompliance((data as SmsComplianceRow | null) ?? null) },
		{ headers: noStore }
	);
};

// Save the organization's compliance settings. The upsert command creates the row on first save and updates it
// after; validation caps the wording and holds the interval to 1-60 days.
export const PATCH: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = smsComplianceSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the compliance settings.',
				field_errors: smsSettingsFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const result = await getOwnerSupabaseClient().rpc('communication_sms_set_compliance_settings', {
		p_organization_id: check.auth.organization.id,
		p_opt_out_enabled: parsed.data.opt_out_enabled,
		// The command applies nullif(btrim(...), '') itself, so an empty string clears the custom wording back to
		// the system default -- identical to the null the schema normalises to.
		p_opt_out_text: parsed.data.opt_out_text ?? '',
		p_sender_info_enabled: parsed.data.sender_info_enabled,
		p_sender_info_text: parsed.data.sender_info_text ?? '',
		p_periodic_reinsert_days: parsed.data.periodic_reinsert_days,
		p_actor: check.auth.user.id
	});

	if (result.error) {
		if (result.error.code === 'P0001') {
			return json({ error: result.error.message }, { status: 409, headers: noStore });
		}
		console.error('Could not save the SMS compliance settings.', result.error);
		return json(
			{ error: 'The compliance settings could not be saved.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(
		{ compliance: safeSmsCompliance(result.data as SmsComplianceRow) },
		{ headers: noStore }
	);
};
