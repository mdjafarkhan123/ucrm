import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { loadReviewCampaignActivity, loadReviewSettings } from '$lib/server/reviews/settings';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

// Jafar may inspect the contractor-owned review link and campaign readiness, never connect or change it
// (docs/jafar-completion-contract.md). Read-only: no POST exists here, matching the Stripe connection slice's
// narrower scope for a fully contractor-owned setup.
const noStore = { 'cache-control': 'no-store' };

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const [settings, activity] = await Promise.all([
			loadReviewSettings(parsedOrganizationId.data),
			loadReviewCampaignActivity(parsedOrganizationId.data)
		]);
		return json(
			{
				campaign: {
					google_review_url: settings.google_review_url,
					routing_enabled: settings.routing_enabled,
					routing_google_min_rating: settings.routing_google_min_rating,
					routing_acknowledged_at: settings.routing_acknowledged_at,
					channel_readiness: settings.readiness,
					updated_at: settings.updated_at,
					activity_30d: activity
				}
			},
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not load the organization review campaign status.', error);
		return json(
			{ error: 'Review campaign status could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
};
