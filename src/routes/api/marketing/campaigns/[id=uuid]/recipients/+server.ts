import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { listCampaignRecipients } from '$lib/server/marketing/campaigns';

// The Recipients tab (blueprint §12): a searchable, bounded, keyset-paginated list. Needs marketing.view.

const recipientsQuerySchema = z.object({
	cursor: z.string().min(3).max(400).optional(),
	status: z
		.enum(['waiting', 'delivered', 'failed', 'excluded', 'unsubscribed', 'engaged'])
		.optional(),
	search: z.string().trim().max(160).optional()
});

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	const parsed = recipientsQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const page = await listCampaignRecipients(access.auth.organization.id, event.params.id, {
			cursor: parsed.data.cursor,
			statusFilter: parsed.data.status,
			search: parsed.data.search
		});
		return json(page, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not load marketing campaign recipients.', error);
		return databaseError();
	}
};
