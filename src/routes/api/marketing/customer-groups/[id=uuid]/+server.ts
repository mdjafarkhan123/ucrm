import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { marketingGroupRulesSchema } from '$lib/marketing/customer-groups';
import {
	archiveCustomerGroup,
	GroupChangedError,
	GroupNameTakenError,
	updateCustomerGroup
} from '$lib/server/marketing/customer-groups';

// Editing and removing one saved group. Both need marketing.draft.

const updateSchema = z.object({
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
	rules: marketingGroupRulesSchema,
	// The revision the editor loaded. Someone else's newer save is never silently replaced.
	revision: z.number().int().min(1)
});

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
		const group = await updateCustomerGroup(
			access.auth.organization.id,
			access.auth.user.id,
			event.params.id,
			revision,
			input
		);
		return json({ group }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof GroupNameTakenError) {
			return validationError({ name: 'You already have a group with that name.' });
		}
		if (error instanceof GroupChangedError) {
			return json(
				{
					error:
						'Someone else changed this group while you were editing it. Reopen it to see their version.',
					reason: 'stale_revision'
				},
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		}
		console.error('Could not update a marketing customer group.', error);
		return databaseError();
	}
};

export const DELETE: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	try {
		const removed = await archiveCustomerGroup(access.auth.organization.id, event.params.id);
		if (!removed) return notFound('That customer group no longer exists.');
		return json({ ok: true }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not archive a marketing customer group.', error);
		return databaseError();
	}
};
