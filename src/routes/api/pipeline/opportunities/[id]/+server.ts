import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { toBoardCard, type BoardPageRow } from '$lib/server/pipeline/card';

const NOT_FOUND = 'That card is no longer open on the Pipeline.';

// One board card by its id, for a Brief opened from a link -- a Task on the Schedule today, an alert later.
// It reads through `pipeline_opportunity_card`, which asks the board's own `pipeline_board_page` for this one
// card, so every rule the board applies (tenant, pipeline access, client visibility, money) applies here too.
// A card that is won, lost, closed, or not the caller's to see is simply not found.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);

	const { data, error } = await event.locals.supabase.rpc('pipeline_opportunity_card', {
		target_opportunity_id: event.params.id
	});
	if (error) {
		if (error.code === '42501') return notFound(NOT_FOUND);
		return databaseError();
	}

	const row = (data as BoardPageRow[] | null)?.[0];
	if (!row) return notFound(NOT_FOUND);

	return json(toBoardCard(row, hasPermission(check.access, 'pipeline.view_value')), {
		headers: PRIVATE_READ_HEADERS
	});
};
