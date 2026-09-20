import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import { loadMarketingDeliveryOptions } from '$lib/server/marketing/delivery-options';

// What the Delivery step (blueprint §8 step 4) shows and offers: the sender/reply identity, business phone
// and website, the forms a call to action could point at, and the Marketing allowance. Same permission as
// reading a campaign -- this is a read, not a draft edit.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const options = await loadMarketingDeliveryOptions(access.auth.organization.id);
		return json(
			{ ...options, organization_slug: access.auth.organization.slug },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not load Marketing delivery options.', error);
		return databaseError();
	}
};
