import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import { savePackageOfferArgs } from '$lib/server/packages/package-offer-args';
import {
	packageFieldErrors,
	packageOfferActionSchema,
	packageOfferIdSchema
} from '$lib/server/validation/package-builder.schema';

// Package builder P11b: save the offer Jafar loaded (at the revision he loaded), or archive and restore it.
// Archiving stops new claims only; customers who claimed it keep their months.

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const offerId = packageOfferIdSchema.safeParse(event.params.offerId);
	if (!offerId.success) return json({ error: offerId.error.issues[0].message }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = packageOfferActionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the offer.', field_errors: packageFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const client = getOwnerSupabaseClient();
	const command = parsed.data;
	const { data, error } =
		command.action === 'save'
			? await client.rpc(
					'save_package_offer',
					savePackageOfferArgs(command.terms, {
						offerId: offerId.data,
						expectedRevision: command.expected_revision,
						actorEmail: session.email,
						// A save is guarded by its revision, so the key only has to be unique.
						idempotencyKey: crypto.randomUUID()
					})
				)
			: await client.rpc('set_package_offer_archived', {
					offer_id: offerId.data,
					archived: command.action === 'archive',
					actor_owner_email: session.email
				});
	if (error) {
		if (error.code === 'P0409')
			return json({ error: error.message, reason: 'stale' }, { status: 409 });
		if (error.code === '23503') return json({ error: error.message }, { status: 404 });
		const refused = ownerPackageCommandError(error);
		if (refused) return refused;
		console.error('Could not change the offer.', error);
		return json({ error: 'The offer could not be saved.' }, { status: 500 });
	}
	return json({ result: data });
};
