import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { hydrateRuleLabels } from '$lib/server/marketing/customer-groups';

// Names for ids the rule builder already holds -- reopening a saved group's catalog-item and Customer
// selections needs their labels, not just the ids the rule stores. Read-only, so `marketing.view` is enough.

const idList = (max: number) => z.array(z.string().uuid()).max(max).default([]);

const labelsSchema = z.object({
	catalog_item_ids: idList(50),
	client_ids: idList(500)
});

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = labelsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const labels = await hydrateRuleLabels(
			access.auth.organization.id,
			parsed.data.catalog_item_ids,
			parsed.data.client_ids
		);
		return json(labels, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not look up marketing rule labels.', error);
		return databaseError();
	}
};
