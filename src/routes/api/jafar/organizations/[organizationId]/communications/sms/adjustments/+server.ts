import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsAdjustmentSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-6: list one organization's standalone SMS ledger adjustments for the Jafar Commercial access tab.
// Read-only; adjustments are posted by the POST route below.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: entries, error } = await client
			.from('communication_sms_credit_ledger_entries')
			.select('id, amount_minor, balance_after_minor, reason, occurred_at')
			.eq('organization_id', parsedOrganizationId.data)
			.eq('entry_kind', 'adjustment')
			.order('occurred_at', { ascending: false });
		if (error) throw error;

		return json({ entries: entries ?? [] }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the SMS adjustments.', error);
		return json({ error: 'The SMS adjustments could not be loaded.' }, { status: 500 });
	}
};

// Stage 2C-5b: the platform owner posts a reasoned, standalone correction (either sign) to an organization's
// settled SMS balance. The database command (20260917130000) is retry-safe: the same idempotency_key returns
// the prior ledger entry instead of posting a second one, so we only audit a genuinely new post (result.applied).
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

	const parsed = communicationSmsAdjustmentSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the adjustment.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) {
		return json(
			{ error: 'Confirm your password before recording an adjustment.', step_up_required: true },
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_sms_record_adjustment', {
			p_organization_id: parsedOrganizationId.data,
			p_amount_minor: parsed.data.amount_minor,
			p_reason: parsed.data.reason,
			p_idempotency_key: parsed.data.idempotency_key,
			p_actor: PLATFORM_OWNER_ACTOR_ID
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		const entry = result.data?.[0] ?? null;
		if (!entry) throw new Error('The adjustment command returned no row.');

		if (entry.applied) {
			await recordOwnerAccessAudit(client, {
				organization_id: parsedOrganizationId.data,
				email: session.email,
				event_type: 'communication_sms_adjustment_recorded',
				target_type: 'communication_sms_credit_ledger_entry',
				target_key: entry.id,
				before_state: null,
				after_state: entry
			});
		}

		return json({ entry }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not record the SMS adjustment.', error);
		return json({ error: 'The adjustment could not be recorded.' }, { status: 500 });
	}
};
