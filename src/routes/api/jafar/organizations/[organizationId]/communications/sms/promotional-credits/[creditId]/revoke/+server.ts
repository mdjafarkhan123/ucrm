import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsPromotionalCreditRevokeSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-5b: revoke an active promotional grant on this organization. The revoke command is not
// organization-scoped, so we look the grant up first and confirm it belongs to this organization -- the
// same pre-check pattern as the hold release route.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedCreditId = organizationIdSchema.safeParse(event.params.creditId);
	if (!parsedOrganizationId.success || !parsedCreditId.success) {
		return json({ error: 'The promotional credit identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsPromotionalCreditRevokeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the revocation.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before revoking promotional credit.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await client
			.from('communication_sms_promotional_credits')
			.select('id, organization_id, status')
			.eq('id', parsedCreditId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing || existing.organization_id !== parsedOrganizationId.data) {
			return json({ error: 'That promotional credit was not found.' }, { status: 404 });
		}

		const result = await client.rpc('communication_sms_revoke_promotional_credit', {
			p_credit_id: parsedCreditId.data,
			p_revoked_by: PLATFORM_OWNER_ACTOR_ID,
			p_reason: parsed.data.reason
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
			event_type: 'communication_sms_promotional_credit_revoked',
			target_type: 'communication_sms_promotional_credit',
			target_key: parsedCreditId.data,
			before_state: { status: existing.status },
			after_state: result.data
		});

		return json({ credit: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not revoke the promotional credit.', error);
		return json({ error: 'The promotional credit could not be revoked.' }, { status: 500 });
	}
};
