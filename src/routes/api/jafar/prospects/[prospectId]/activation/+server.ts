import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	prospectActivationPreviewSchema,
	prospectIdSchema
} from '$lib/server/validation/prospect.schema';

// Package builder P10: what activation will record — the edition, billing, payment, credit, and exact
// covered dates — for Jafar to review before he activates. P11b: with the offer decision or code he chose.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	const parsed = prospectActivationPreviewSchema.safeParse({
		offer_decision: event.url.searchParams.get('offer_decision') || null,
		offer_code: event.url.searchParams.get('offer_code') || null
	});
	if (!parsed.success) return json({ error: parsed.error.issues[0].message }, { status: 422 });

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc(
			'owner_onboarding_activation_preview',
			{
				target_application_id: parsedId.data,
				offer_decision: parsed.data.offer_decision ?? undefined,
				offer_code: parsed.data.offer_code ?? undefined
			}
		);
		if (error) throw error;
		if (!data) return json({ error: 'Prospect was not found.' }, { status: 404 });
		return json({ preview: data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not preview the activation.', error);
		return json({ error: 'The activation could not be previewed.' }, { status: 500 });
	}
};
