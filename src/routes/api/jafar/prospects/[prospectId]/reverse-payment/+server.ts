import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import {
	prospectIdSchema,
	prospectPaymentReversalSchema
} from '$lib/server/validation/prospect.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

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

	const parsed = prospectPaymentReversalSchema.safeParse(body);
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
		const { data: application, error: applicationError } = await client
			.from('platform_onboarding_applications')
			.select('business_name')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (applicationError) throw applicationError;
		if (!application) return json({ error: 'Prospect was not found.' }, { status: 404 });

		const { error: rpcError } = await client.rpc('reverse_onboarding_application_payment', {
			target_application_id: parsedId.data,
			actor_email: session.email,
			reason: parsed.data.reason
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (
				rpcError.message.includes('can be reversed') ||
				rpcError.message.includes('already reversed') ||
				rpcError.message.includes('No payment confirmation exists')
			)
				return json({ error: rpcError.message }, { status: 409 });
			throw rpcError;
		}

		try {
			await raiseOwnerAlert(client, {
				kind: 'onboarding_application_payment_reversed',
				severity: 'urgent',
				title: `Payment reversed for ${application.business_name}`,
				body: parsed.data.reason,
				target: { targetKind: 'onboarding_application', targetId: parsedId.data },
				origin: event.url.origin
			});
		} catch (alertError) {
			console.error('Could not raise the payment-reversal alert.', alertError);
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not reverse the prospect payment.', error);
		return json({ error: 'The payment could not be reversed.' }, { status: 500 });
	}
};
