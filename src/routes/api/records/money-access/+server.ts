import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

// What the money summary card on a New job, quote or invoice may show before anything is saved. The lines
// on those pages already carry their unit cost, so the only question is whether this person may see cost
// and profit at all, and the business's target margin to measure a projected profit against. The target
// is read through RLS, so a reader its policy does not cover simply gets no target.
export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });
	}

	try {
		const access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
		const jobCost = hasPermission(access, 'jobs.view_cost');
		const quoteCost = hasPermission(access, 'quotes.view_cost');

		let targetMarginBasisPoints: number | null = null;
		if (jobCost || quoteCost) {
			const { data } = await event.locals.supabase
				.from('organization_quote_target_margin')
				.select('target_margin_basis_points')
				.eq('organization_id', auth.organization.id)
				.maybeSingle();
			targetMarginBasisPoints = data?.target_margin_basis_points ?? null;
		}

		return json(
			{
				// An invoice's profit is the job-costing figure, so it follows the job-costing permission.
				can_see_cost: { job: jobCost, quote: quoteCost, invoice: jobCost },
				target_margin_basis_points: targetMarginBasisPoints
			},
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not resolve money access.', error);
		return json({ error: 'Access could not be verified.' }, { status: 500 });
	}
};
