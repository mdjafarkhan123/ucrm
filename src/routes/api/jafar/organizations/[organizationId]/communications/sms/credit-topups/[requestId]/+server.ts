import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { Json } from '$lib/database.types';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsCreditTopupDecisionSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-5a: the platform owner confirms or rejects an offsite SMS credit top-up request. Confirming
// posts one immutable ledger credit and raises the organization's settled balance; both decisions are
// money actions, so each requires a fresh password reconfirmation (step-up).
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedRequestId = organizationIdSchema.safeParse(event.params.requestId);
	if (!parsedOrganizationId.success || !parsedRequestId.success) {
		return json({ error: 'The request identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsCreditTopupDecisionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the top-up decision.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before deciding a credit top-up.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		// Scope the request to this organization before acting, so a mismatched id is a clean 404 rather
		// than a friendly-but-confusing 409 from the database's own not-found guard.
		const { data: existing, error: existingError } = await client
			.from('communication_sms_credit_topup_requests')
			.select('id, organization_id, status')
			.eq('id', parsedRequestId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing || existing.organization_id !== parsedOrganizationId.data) {
			return json({ error: 'That top-up request was not found.' }, { status: 404 });
		}

		const result =
			parsed.data.action === 'confirm'
				? await client.rpc('communication_sms_confirm_credit_topup', {
						p_request_id: parsedRequestId.data,
						p_decided_by: PLATFORM_OWNER_ACTOR_ID,
						p_settled_amount_minor: parsed.data.settled_amount_minor,
						p_decision_reason: parsed.data.decision_reason ?? undefined
					})
				: await client.rpc('communication_sms_reject_credit_topup', {
						p_request_id: parsedRequestId.data,
						p_decided_by: PLATFORM_OWNER_ACTOR_ID,
						p_decision_reason: parsed.data.decision_reason
					});

		if (result.error) {
			if (result.error.code === '23503') {
				return json({ error: 'That top-up request was not found.' }, { status: 404 });
			}
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type:
				parsed.data.action === 'confirm'
					? 'communication_sms_credit_topup_confirmed'
					: 'communication_sms_credit_topup_rejected',
			target_type: 'communication_sms_credit_topup_request',
			target_key: parsedRequestId.data,
			before_state: { status: existing.status },
			after_state: result.data as unknown as Json
		});

		return json({ request: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not decide the SMS credit top-up.', error);
		return json({ error: 'The credit top-up decision could not be recorded.' }, { status: 500 });
	}
};
