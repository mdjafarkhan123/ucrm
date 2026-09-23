import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	CampaignChangedError,
	CampaignInvalidError,
	launchCampaign
} from '$lib/server/marketing/campaigns';
import { loadMarketingReadiness } from '$lib/server/marketing/readiness';

// Confirming a campaign -- "Send now" or "Schedule for later" in CampaignReviewStep.svelte. Needs
// marketing.launch (stricter than the marketing.draft that saves a draft), and readiness is checked here,
// not inside marketing_launch_campaign, matching every other Marketing command's split (the RPC trusts the
// organization it is given; the route proves the caller may act and that Marketing is actually usable).

const launchSchema = z.object({
	revision: z.number().int().min(1),
	send_at: z.string().datetime().nullable(),
	idempotency_key: z.string().uuid('Start a new launch attempt and try again.')
});

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.launch');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = launchSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;

	try {
		const readiness = await loadMarketingReadiness(organizationId);
		if (!readiness.ready) {
			return json(
				{
					error: "Marketing isn't ready to send yet.",
					reason: 'not_ready',
					reasons: readiness.reasons
				},
				{ status: 422, headers: NO_STORE_HEADERS }
			);
		}

		const result = await launchCampaign(
			organizationId,
			access.auth.user.id,
			event.params.id,
			parsed.data.revision,
			parsed.data.send_at,
			parsed.data.idempotency_key
		);
		return json(result, { headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof CampaignInvalidError) {
			return validationError({ form: error.message });
		}
		if (error instanceof CampaignChangedError) {
			return json(
				{
					error:
						'Someone else changed this campaign while you were editing it. Reload it to see their version.',
					reason: 'stale_revision'
				},
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		}
		console.error('Could not launch a marketing campaign.', error);
		return databaseError();
	}
};
