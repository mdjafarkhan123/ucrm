import type { LayoutServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import { getOrganizationContext } from '$lib/server/auth/organization';

export const load: LayoutServerLoad = async (event) => {
	const user = await requireContractor(event);
	const context = await getOrganizationContext(event, user);

	return context ?? { user, organization: null };
};
