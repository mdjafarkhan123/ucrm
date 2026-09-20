import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	MARKETING_CAMPAIGN_NAME_MAX,
	marketingCampaignContentSchema,
	marketingGoals
} from '$lib/marketing/campaign-content';
import {
	CampaignChangedError,
	CampaignInvalidError,
	deleteCampaignDraft,
	getCampaign,
	updateCampaignDraft
} from '$lib/server/marketing/campaigns';

// One campaign draft. Reading needs marketing.view; saving or removing it needs marketing.draft.

const updateSchema = z.object({
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
	content: marketingCampaignContentSchema,
	// The revision the editor loaded. Someone else's newer save is never silently replaced.
	revision: z.number().int().min(1)
});

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const campaign = await getCampaign(access.auth.organization.id, event.params.id);
		if (!campaign) return notFound('That campaign no longer exists.');
		return json({ campaign }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not load a marketing campaign.', error);
		return databaseError();
	}
};

export const PATCH: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { revision, ...input } = parsed.data;

	try {
		const result = await updateCampaignDraft(
			access.auth.organization.id,
			access.auth.user.id,
			event.params.id,
			revision,
			input
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
		console.error('Could not update a marketing campaign.', error);
		return databaseError();
	}
};

export const DELETE: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	try {
		const removed = await deleteCampaignDraft(access.auth.organization.id, event.params.id);
		if (!removed) return notFound('That campaign no longer exists.');
		return json({ ok: true }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not delete a marketing campaign.', error);
		return databaseError();
	}
};
