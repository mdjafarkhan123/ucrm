import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import {
	createPackageOfferSchema,
	packageFieldErrors
} from '$lib/server/validation/package-builder.schema';
import { savePackageOfferArgs } from '$lib/server/packages/package-offer-args';

// Package builder P11b: every introductory offer with its status and claims, and new offers. The rules
// live in save_package_offer (P11a); this route validates the form and names the owner who saved it.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_package_offers');
	if (error) {
		console.error('Could not load the package offers.', error);
		return json({ error: 'Offers could not be loaded.' }, { status: 500 });
	}
	return json({ offers: data ?? [] }, { headers: { 'cache-control': 'no-store' } });
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = createPackageOfferSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the offer.', field_errors: packageFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'save_package_offer',
		savePackageOfferArgs(parsed.data.terms, {
			offerId: null,
			expectedRevision: 0,
			actorEmail: session.email,
			idempotencyKey: parsed.data.idempotency_key
		})
	);
	if (error) {
		const refused = ownerPackageCommandError(error);
		if (refused) return refused;
		console.error('Could not create the offer.', error);
		return json({ error: 'The offer could not be created.' }, { status: 500 });
	}
	return json({ result: data }, { status: 201 });
};
