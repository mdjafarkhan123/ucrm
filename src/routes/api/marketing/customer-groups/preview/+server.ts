import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { marketingGroupRulesSchema } from '$lib/marketing/customer-groups';
import { previewCounts, previewRecipients } from '$lib/server/marketing/customer-groups';

// Exactly who a rule set would reach right now. This is a read, but the rules are a structured object, so
// it takes a POST body and validates it like every other write does.
//
// The counts view is one pass over the organization's customers. The list view returns one bounded page,
// continued with the last row's name and id rather than an offset, so a deep page costs the same as the
// first.

const previewSchema = z.object({
	rules: marketingGroupRulesSchema,
	view: z.enum(['counts', 'recipients']).default('counts'),
	status: z.enum(['all', 'eligible', 'excluded']).default('all'),
	after_display_name: z.string().max(300).optional(),
	after_client_id: z.string().uuid().optional(),
	page_size: z.number().int().min(1).max(200).default(50)
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

	const parsed = previewSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;
	const { rules, view, status, after_display_name, after_client_id, page_size } = parsed.data;

	try {
		if (view === 'counts') {
			const counts = await previewCounts(organizationId, rules);
			return json({ counts }, { headers: NO_STORE_HEADERS });
		}

		const recipients = await previewRecipients(organizationId, rules, {
			status,
			after_display_name,
			after_client_id,
			page_size
		});
		return json({ recipients }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not preview marketing recipients.', error);
		return databaseError();
	}
};
