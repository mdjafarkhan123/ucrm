import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadPublicPackages } from '$lib/server/packages/public-packages';

// Jafar business management B4: the packages on the public pricing page today, for "Pricing shared". Sales can
// read them here without opening the Packages area.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		const packages = await loadPublicPackages(getOwnerSupabaseClient());
		return json(
			{
				packages: packages.map((pkg) => ({
					slug: pkg.slug,
					name: pkg.name,
					monthly_price_usd_cents: pkg.monthly_price_usd_cents,
					yearly_price_usd_cents: pkg.yearly_price_usd_cents
				}))
			},
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not load the pricing page packages.', error);
		return json({ error: 'The packages could not be loaded.' }, { status: 500 });
	}
};
