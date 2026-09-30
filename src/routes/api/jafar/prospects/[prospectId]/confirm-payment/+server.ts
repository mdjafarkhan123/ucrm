import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	prospectIdSchema,
	prospectPaymentConfirmationSchema
} from '$lib/server/validation/prospect.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// Package builder P10: the initial payment is recorded as a receipt on the application. It must reach
// the agreed first-period price; activation later moves it into the organization's billing ledger.

function dollars(cents: number) {
	return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = prospectPaymentConfirmationSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	try {
		const client = getOwnerSupabaseClient();
		const { error: rpcError } = await client.rpc('confirm_onboarding_application_payment', {
			target_application_id: parsedId.data,
			actor_email: session.email,
			received_on: parsed.data.received_on,
			amount_usd_cents: parsed.data.amount_usd_cents,
			method: parsed.data.method,
			private_reference: parsed.data.private_reference,
			note: parsed.data.note ?? undefined
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			const shortfall = /agreed first payment of (\d+) cents/.exec(rpcError.message);
			if (shortfall) {
				const message = `This is less than the agreed first payment of ${dollars(Number(shortfall[1]))}. Record it once the full amount has arrived.`;
				return json(
					{ error: message, field_errors: { amount_usd_cents: message } },
					{ status: 422 }
				);
			}
			if (rpcError.message.includes('in the future'))
				return json(
					{ error: rpcError.message, field_errors: { received_on: rpcError.message } },
					{ status: 422 }
				);
			if (
				rpcError.message.includes('can no longer be confirmed') ||
				rpcError.message.includes('already has a confirmed payment')
			)
				return json({ error: rpcError.message }, { status: 409 });
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not confirm the prospect payment.', error);
		return json({ error: 'The payment could not be confirmed.' }, { status: 500 });
	}
};
