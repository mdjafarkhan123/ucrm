import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { prospectIdSchema, prospectCorrectionSchema } from '$lib/server/validation/prospect.schema';
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

	const parsed = prospectCorrectionSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	const { reason, ...fields } = parsed.data;

	try {
		const client = getOwnerSupabaseClient();
		const { error: rpcError } = await client.rpc('correct_onboarding_application', {
			target_application_id: parsedId.data,
			actor_email: session.email,
			correction_reason: reason,
			new_business_name: fields.business_name,
			new_main_contact_name: fields.main_contact_name,
			new_main_contact_email: fields.main_contact_email,
			new_main_contact_phone: fields.main_contact_phone,
			new_initial_administrator_name: (fields.initial_administrator_name ?? null) as string,
			new_initial_administrator_email: (fields.initial_administrator_email ?? null) as string,
			new_trade: fields.trade,
			new_city_country: fields.city_country,
			new_time_zone: fields.time_zone,
			new_note: (fields.note ?? null) as string
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (rpcError.message.includes('can no longer be corrected'))
				return json({ error: rpcError.message }, { status: 409 });
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not correct the prospect.', error);
		return json({ error: 'The correction could not be saved.' }, { status: 500 });
	}
};
