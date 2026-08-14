import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	organizationCommercialCommandSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const originalEventSelect =
	'id, event_kind, occurred_at, summary, amount_usd_cents, paid_through_after, private_reference';

async function getCommercialState(organizationId: string) {
	const client = getOwnerSupabaseClient();
	const [
		{ data: organization, error: organizationError },
		{ data: state, error: stateError },
		{ data: settings, error: settingsError },
		{ data: originalEvents, error: originalEventsError }
	] = await Promise.all([
		client
			.from('organizations')
			.select('id, name, lifecycle_status')
			.eq('id', organizationId)
			.maybeSingle(),
		client
			.from('organization_commercial_state')
			.select(
				'paid_through_date, paid_through_source, grace_ends_at, grace_basis_timezone, last_event_id, state_version, updated_at'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_commercial_settings')
			.select('commercial_timezone, timezone_source')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_commercial_events')
			.select(originalEventSelect)
			.eq('organization_id', organizationId)
			.in('event_kind', ['initial_payment_confirmed', 'renewal_confirmed'])
			.order('occurred_at', { ascending: false })
			.order('id', { ascending: false })
	]);

	if (organizationError) throw organizationError;
	if (stateError) throw stateError;
	if (settingsError) throw settingsError;
	if (originalEventsError) throw originalEventsError;
	if (!organization) return null;

	return { organization, state, settings, original_events: originalEvents ?? [] };
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const state = await getCommercialState(parsedId.data);
		return state ? json(state) : json({ error: 'Organization was not found.' }, { status: 404 });
	} catch (error) {
		console.error('Could not load organization commercial access.', error);
		return json({ error: 'Commercial access could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = organizationCommercialCommandSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the commercial action.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (
		parsed.data.action === 'renewal' &&
		parsed.data.reactivate &&
		!consumeOwnerStepUp(event, session)
	) {
		return json(
			{
				error: 'Confirm your password before recording a renewal and reactivating.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const current = await getCommercialState(parsedId.data);
		if (!current) return json({ error: 'Organization was not found.' }, { status: 404 });
		if (
			parsed.data.action === 'renewal' &&
			parsed.data.reactivate &&
			current.organization.lifecycle_status !== 'suspended'
		) {
			return json(
				{ error: 'Only a suspended organization can be reactivated with a renewal.' },
				{ status: 409 }
			);
		}

		const client = getOwnerSupabaseClient();
		const paidThroughArgs = {
			paid_through_effect: parsed.data.paid_through_effect,
			...(parsed.data.paid_through_effect === 'set'
				? { paid_through_date: parsed.data.paid_through_date ?? undefined }
				: {})
		};
		const safePayload =
			parsed.data.paid_through_effect === 'set'
				? { paid_through_date: parsed.data.paid_through_date }
				: {};

		const result =
			parsed.data.action === 'renewal'
				? await client.rpc('apply_organization_late_renewal_reactivation', {
						target_organization_id: parsedId.data,
						idempotency_key: parsed.data.idempotency_key,
						summary: 'Renewal recorded.',
						...paidThroughArgs,
						actor_owner_email: session.email,
						private_reason: parsed.data.private_reason ?? undefined,
						private_reference: parsed.data.private_reference,
						amount_usd_cents: parsed.data.amount_usd_cents,
						reactivate: parsed.data.reactivate,
						safe_kind: 'renewal_recorded',
						safe_payload: safePayload
					})
				: await client.rpc('apply_organization_commercial_command', {
						target_organization_id: parsedId.data,
						event_kind:
							parsed.data.action === 'correction'
								? 'payment_correction_recorded'
								: parsed.data.action === 'refund'
									? 'refund_recorded'
									: 'payment_reversal_recorded',
						idempotency_key: parsed.data.idempotency_key,
						summary:
							parsed.data.action === 'correction'
								? 'Payment correction recorded.'
								: parsed.data.action === 'refund'
									? 'Refund recorded.'
									: 'Payment reversal recorded.',
						...paidThroughArgs,
						actor_owner_email: session.email,
						private_reason: parsed.data.private_reason ?? undefined,
						private_reference: parsed.data.private_reference,
						amount_usd_cents: parsed.data.amount_usd_cents,
						original_confirmation_id: parsed.data.original_event_id,
						safe_kind: 'access_period_updated',
						safe_payload: safePayload
					});

		if (result.error) {
			if (result.error.code === '40001') {
				return json(
					{ error: 'Commercial access changed. Review it and try again.' },
					{ status: 409 }
				);
			}
			if (['23503', '23514'].includes(result.error.code)) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		const next = await getCommercialState(parsedId.data);
		return json({ command: result.data, ...(next ?? {}) });
	} catch (error) {
		console.error('Could not record organization commercial action.', error);
		return json({ error: 'The commercial action could not be recorded.' }, { status: 500 });
	}
};
