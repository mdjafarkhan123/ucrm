import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	safeSmsCreditTopupRequest,
	type SmsCreditTopupRequestRow
} from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

// Stage 3D: cancel one of the organization's own SMS credit top-up requests. Only a still-awaiting request may
// be cancelled -- confirmed money stands, and a decided request never reopens (matches
// communication_sms_cancel_credit_topup's own guard).
export const PATCH: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const parsedRequestId = organizationIdSchema.safeParse(event.params.requestId);
	if (!parsedRequestId.success) {
		return json({ error: 'The request identifier is invalid.' }, { status: 422, headers: noStore });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	if (!body || (body as { action?: unknown }).action !== 'cancel') {
		return json({ error: 'That action is not supported.' }, { status: 422, headers: noStore });
	}

	const client = getOwnerSupabaseClient();
	const organizationId = check.auth.organization.id;

	// Scope to this organization before acting, so a request that belongs to someone else is a clean 404
	// rather than the database's own not-found guard leaking a confusing 409.
	const { data: existing, error: existingError } = await client
		.from('communication_sms_credit_topup_requests')
		.select('id, organization_id')
		.eq('id', parsedRequestId.data)
		.maybeSingle();
	if (existingError) {
		console.error('Could not look up the SMS credit top-up request.', existingError);
		return json(
			{ error: 'The top-up request could not be cancelled.' },
			{ status: 500, headers: noStore }
		);
	}
	if (!existing || existing.organization_id !== organizationId) {
		return json({ error: 'That top-up request was not found.' }, { status: 404, headers: noStore });
	}

	const result = await client.rpc('communication_sms_cancel_credit_topup', {
		p_request_id: parsedRequestId.data,
		p_cancelled_by: check.auth.user.id
	});

	if (result.error) {
		if (result.error.code === 'P0001') {
			return json({ error: result.error.message }, { status: 409, headers: noStore });
		}
		console.error('Could not cancel the SMS credit top-up request.', result.error);
		return json(
			{ error: 'The top-up request could not be cancelled.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(
		{ request: safeSmsCreditTopupRequest(result.data as SmsCreditTopupRequestRow) },
		{ headers: noStore }
	);
};
