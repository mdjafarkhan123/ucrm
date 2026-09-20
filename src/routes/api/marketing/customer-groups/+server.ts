import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { marketingGroupRulesSchema } from '$lib/marketing/customer-groups';
import {
	createCustomerGroup,
	GroupNameTakenError,
	listCustomerGroups
} from '$lib/server/marketing/customer-groups';

// The organization's saved recipient rules. Viewing needs marketing.view; saving a new one needs
// marketing.draft. Both permissions already fold in the plan, so an organization without Marketing gets a
// clear 403 and no data.

const saveSchema = z.object({
	name: z
		.string()
		.trim()
		.min(1, 'Give this group a name.')
		.max(120, 'Keep the name under 120 characters.'),
	description: z
		.string()
		.trim()
		.max(500, 'Keep the description under 500 characters.')
		.optional()
		.transform((value) => (value ? value : undefined)),
	rules: marketingGroupRulesSchema
});

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const groups = await listCustomerGroups(access.auth.organization.id);
		return json({ groups }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not list marketing customer groups.', error);
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

	const parsed = saveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const group = await createCustomerGroup(
			access.auth.organization.id,
			access.auth.user.id,
			parsed.data
		);
		return json({ group }, { status: 201, headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof GroupNameTakenError) {
			return validationError({ name: 'You already have a group with that name.' });
		}
		console.error('Could not create a marketing customer group.', error);
		return databaseError();
	}
};
