import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound, validationError, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readBody } from '$lib/server/jafar/lead-approval';
import { DEAL_NOT_FOUND, dealCommandResponse } from '$lib/server/jafar/deals';
import { loadPublicPackages } from '$lib/server/packages/public-packages';
import { dealShareSchema } from '$lib/server/validation/deal.schema';

// Jafar business management B4: record the packages shared with a Deal. The prices and offers are read here from
// the pricing page as it stands now -- never taken from the browser -- and copied onto the Deal, so a later price
// change leaves what the business saw untouched.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(DEAL_NOT_FOUND);

	const body = await readBody(event.request, dealShareSchema);
	if ('response' in body) return body.response;

	const client = getOwnerSupabaseClient();
	let published;
	try {
		published = await loadPublicPackages(client);
	} catch (error) {
		console.error('Could not read the pricing page for a Deal.', error);
		return databaseError();
	}

	const shared = [];
	for (const slug of body.data.package_slugs) {
		const pkg = published.find((item) => item.slug === slug);
		if (!pkg)
			return validationError(
				{ package_slugs: 'One of these packages is no longer on the pricing page. Choose again.' },
				409
			);
		const link = new URL(`/packages/${pkg.slug}`, event.url.origin);
		if (body.data.billing === 'year' && pkg.yearly_price_usd_cents !== null)
			link.searchParams.set('billing', 'year');
		shared.push({
			edition_id: pkg.edition_id,
			slug: pkg.slug,
			name: pkg.name,
			monthly_price_usd_cents: pkg.monthly_price_usd_cents,
			yearly_price_usd_cents: pkg.yearly_price_usd_cents,
			offers: pkg.offers,
			link: link.toString()
		});
	}

	const result = await client.rpc('owner_deal_share_pricing', {
		actor_email: session.email,
		target_deal_id: event.params.id,
		shared_packages: shared,
		follow_up: body.data.follow_up.text,
		follow_up_on: body.data.follow_up.due_on
	});
	return dealCommandResponse(result, 'record the pricing shared');
};
