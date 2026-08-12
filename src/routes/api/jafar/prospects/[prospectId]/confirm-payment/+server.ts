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

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
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
		const { data: current, error: currentError } = await client
			.from('platform_onboarding_applications')
			.select('package_version_id')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (currentError) throw currentError;
		if (!current) return json({ error: 'Prospect was not found.' }, { status: 404 });

		const { data: packageVersion, error: packageVersionError } = await client
			.from('platform_package_versions')
			.select('price_usd_cents')
			.eq('id', current.package_version_id)
			.maybeSingle();
		if (packageVersionError) throw packageVersionError;

		const { amount_usd_cents, private_reference, mismatch_reason } = parsed.data;
		const listedPrice = packageVersion?.price_usd_cents ?? null;
		const amountDiffers = listedPrice !== null && listedPrice !== amount_usd_cents;
		if (amountDiffers && !mismatch_reason)
			return json(
				{
					error: 'Please review the highlighted fields.',
					field_errors: { mismatch_reason: 'Enter a reason for the amount mismatch.' }
				},
				{ status: 422 }
			);

		const { error: rpcError } = await client.rpc('confirm_onboarding_application_payment', {
			target_application_id: parsedId.data,
			actor_email: session.email,
			amount_usd_cents,
			private_reference,
			mismatch_reason: (amountDiffers ? (mismatch_reason ?? null) : null) as string
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (rpcError.message.includes('can no longer be confirmed'))
				return json({ error: rpcError.message }, { status: 409 });
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not confirm the prospect payment.', error);
		return json({ error: 'The payment could not be confirmed.' }, { status: 500 });
	}
};
