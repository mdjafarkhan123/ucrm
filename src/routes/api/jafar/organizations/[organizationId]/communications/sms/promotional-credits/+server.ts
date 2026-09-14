import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsPromotionalCreditGrantSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-6: list one organization's promotional SMS credit grants (active, expired and revoked) for the
// Jafar Commercial access tab. Expiry is derived on read here too, matching communication_sms_promotional_
// balance -- a grant past its expires_at is shown as expired even though its stored status stays 'active'.
// Read-only; grants are made and revoked by the POST routes below and alongside.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: credits, error } = await client
			.from('communication_sms_promotional_credits')
			.select(
				'id, currency_code, amount_minor, reason, granted_by, granted_at, expires_at, status, revoked_by, revoked_at, revoke_reason'
			)
			.eq('organization_id', parsedOrganizationId.data)
			.order('granted_at', { ascending: false });
		if (error) throw error;

		return json({ credits: credits ?? [] }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the SMS promotional credits.', error);
		return json({ error: 'The SMS promotional credits could not be loaded.' }, { status: 500 });
	}
};

// Stage 2C-5b: the platform owner grants expiring promotional SMS credit to one organization. The database
// command (20260917130000) is retry-safe: calling it again with the same idempotency_key returns the same
// grant instead of a second one, so we only audit a genuinely new grant (result.applied) -- auditing a replay
// would misleadingly suggest two separate grants happened.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsPromotionalCreditGrantSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the promotional credit.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before granting promotional credit.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_sms_grant_promotional_credit', {
			p_organization_id: parsedOrganizationId.data,
			p_amount_minor: parsed.data.amount_minor,
			p_expires_at: parsed.data.expires_at,
			p_reason: parsed.data.reason,
			p_idempotency_key: parsed.data.idempotency_key,
			p_granted_by: PLATFORM_OWNER_ACTOR_ID
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		const credit = result.data?.[0] ?? null;
		if (!credit) throw new Error('The promotional credit command returned no row.');

		if (credit.applied) {
			await recordOwnerAccessAudit(client, {
				organization_id: parsedOrganizationId.data,
				email: session.email,
				event_type: 'communication_sms_promotional_credit_granted',
				target_type: 'communication_sms_promotional_credit',
				target_key: credit.id,
				before_state: null,
				after_state: credit
			});
		}

		return json({ credit }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not grant the promotional credit.', error);
		return json({ error: 'The promotional credit could not be granted.' }, { status: 500 });
	}
};
