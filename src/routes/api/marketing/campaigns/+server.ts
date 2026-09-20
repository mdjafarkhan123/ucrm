import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	MARKETING_CAMPAIGN_NAME_MAX,
	marketingCampaignContentSchema,
	marketingGoals
} from '$lib/marketing/campaign-content';
import {
	CampaignInvalidError,
	createCampaign,
	listCampaigns
} from '$lib/server/marketing/campaigns';

// Campaign drafts. Listing needs marketing.view; creating a new draft needs marketing.draft -- same split as
// customer groups.

const draftSchema = z.object({
	name: z
		.string()
		.trim()
		.min(1, 'Give this campaign a name.')
		.max(MARKETING_CAMPAIGN_NAME_MAX, 'Keep the name under 160 characters.'),
	goal: z.enum(marketingGoals),
	customer_group_id: z
		.string()
		.uuid()
		.nullable()
		.optional()
		.transform((value) => value ?? null),
	template_id: z
		.string()
		.uuid()
		.nullable()
		.optional()
		.transform((value) => value ?? null),
	content: marketingCampaignContentSchema
});

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const campaigns = await listCampaigns(access.auth.organization.id);
		return json({ campaigns }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not list marketing campaigns.', error);
		return databaseError();
	}
};

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = draftSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const campaign = await createCampaign(
			access.auth.organization.id,
			access.auth.user.id,
			parsed.data
		);
		return json({ campaign }, { status: 201, headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof CampaignInvalidError) {
			return validationError({ form: error.message });
		}
		console.error('Could not create a marketing campaign.', error);
		return databaseError();
	}
};
