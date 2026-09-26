import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadReviewChannelReadiness } from '$lib/server/reviews/settings';

// Google review Part 4B: what the builder's "Send a review request" step shows beside its channel choice —
// whether each channel can send an automatic message now, and whether a Google review link is saved. Read under
// Automation's own `view` gate, like the SMS number picker, so an automation editor without reviews.manage still
// sees why a step would not send; the worker's effect re-checks all of it when the step runs.
export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;

	try {
		const [readiness, link] = await Promise.all([
			loadReviewChannelReadiness(organizationId),
			getOwnerSupabaseClient()
				.from('review_settings')
				.select('google_review_url')
				.eq('organization_id', organizationId)
				.maybeSingle()
		]);
		if (link.error) throw link.error;
		return json(
			{ ...readiness, has_google_link: Boolean(link.data?.google_review_url) },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not load the automation review readiness.', error);
		return databaseError();
	}
};
