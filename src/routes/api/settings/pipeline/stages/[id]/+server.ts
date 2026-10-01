import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';

// How many cards sit in one custom stage. Settings asks this when somebody reaches for a stage's remove
// button, so the dialog knows whether it has to ask where the cards go. The command that switches the
// stage off counts again for itself; this number only decides what the dialog shows.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	if (!z.string().uuid().safeParse(event.params.id).success)
		return notFound('That stage could not be found.');

	const { data, error } = await event.locals.supabase.rpc('pipeline_custom_stage_card_count', {
		target_organization_id: check.auth.organization.id,
		target_stage_id: event.params.id
	});

	if (error) return databaseError();

	return json({ card_count: data ?? 0 }, { headers: PRIVATE_READ_HEADERS });
};
