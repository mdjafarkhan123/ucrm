import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { CampaignNotCancellableError, cancelCampaign } from '$lib/server/marketing/campaigns';

// Stops a scheduled or sending campaign: unreleased recipients (waiting/checking) never claim, sent email is
// never recalled. Needs marketing.launch, the same permission that started the send. No body, no revision, no
// idempotency key -- content is frozen post-launch, and the row lock plus status check inside
// marketing_cancel_campaign is the whole serialization point (see Memory/campaigns/marketing-growth/parts/M4.md).

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.launch');
	if ('response' in access) return access.response;

	try {
		const result = await cancelCampaign(
			access.auth.organization.id,
			access.auth.user.id,
			event.params.id
		);
		return json(result, { headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof CampaignNotCancellableError) {
			return validationError({ form: 'This campaign can no longer be cancelled.' });
		}
		console.error('Could not cancel a marketing campaign.', error);
		return databaseError();
	}
};
