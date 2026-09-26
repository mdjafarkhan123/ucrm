import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationEmailRetailRateSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

const noStore = { 'cache-control': 'no-store' };

// Part 7B: list every published over-allowance email retail rate version, newest first. The UI groups by
// currency to show each currency's current and scheduled versions alongside its history, the same shape as
// the SMS retail-rates list. Rate versions are immutable (no update/delete), so this is a plain list.
// provider_cost_major is Jafar-only truth never sent to a contractor-facing route.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const { data: rates, error } = await client
			.from('communication_email_retail_rates')
			.select(
				'id, currency_code, retail_rate_major, provider_cost_major, effective_from, note, created_at'
			)
			.order('effective_from', { ascending: false });
		if (error) throw error;

		return json({ rates: rates ?? [] }, { headers: noStore });
	} catch (error) {
		console.error('Could not load the email retail rates.', error);
		return json({ error: 'The email retail rates could not be loaded.' }, { status: 500 });
	}
};

// Part 7B: the platform owner publishes a new over-allowance email retail rate version, priced per 1,000
// recipients (docs/contractor-email-contract.md "Package allowances and counting"). Rate versions are
// immutable -- a change is always a new version, never a rewrite. Publishing a price list is routine (it
// moves no money immediately and only prices sends that happen later), so no step-up is required. The rate
// has no single owning organization, so its audit trail is platform_audit_events.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}

	const parsed = communicationEmailRetailRateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the rate.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_email_set_retail_rate', {
			p_retail_rate_major: parsed.data.retail_rate_major,
			p_set_by: PLATFORM_OWNER_ACTOR_ID,
			p_currency_code: parsed.data.currency_code,
			p_provider_cost_major: parsed.data.provider_cost_major,
			p_effective_from: parsed.data.effective_from,
			p_note: parsed.data.note
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409, headers: noStore });
			}
			throw result.error;
		}

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'communication_email_retail_rate_set',
			target_type: 'communication_email_retail_rate',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ rate: result.data }, { headers: noStore });
	} catch (error) {
		console.error('Could not publish the email retail rate.', error);
		return json({ error: 'The rate could not be published.' }, { status: 500, headers: noStore });
	}
};
