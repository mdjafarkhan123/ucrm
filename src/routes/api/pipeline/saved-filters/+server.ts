import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { createSavedFilterSchema } from '$lib/server/validation/pipeline.schema';
import {
	SAVED_FILTER_COLUMNS,
	canShareFilters,
	presentSavedFilter,
	savedFilterWriteError
} from '$lib/server/pipeline/saved-filters';
import { savedFilterQuery } from '$lib/pipeline/filters';

// The board's saved filters: the caller's own, and the ones shared with the whole team. The table's
// policies decide which rows come back; this only orders and labels them.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('pipeline_saved_filters')
		.select(SAVED_FILTER_COLUMNS)
		.eq('organization_id', check.auth.organization.id)
		.order('name', { ascending: true });
	if (error) return databaseError();

	const canShare = canShareFilters(check.auth);
	return json(
		{
			filters: (data ?? []).map((row) => presentSavedFilter(row, canShare)),
			can_share: canShare
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Saves the board's current controls under a name, for the caller alone or — owners and administrators
// only — for everyone.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = createSavedFilterSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const canShare = canShareFilters(check.auth);
	if (parsed.data.shared && !canShare) {
		return json(
			{ error: 'Only owners and administrators can share filters with the team.' },
			{ status: 403 }
		);
	}

	const query = savedFilterQuery(parsed.data.filters);
	if (!query) return validationError({ form: 'Change at least one filter before saving.' });

	const { data, error } = await event.locals.supabase
		.from('pipeline_saved_filters')
		.insert({
			organization_id: check.auth.organization.id,
			user_id: parsed.data.shared ? null : check.auth.user.id,
			name: parsed.data.name,
			query
		})
		.select(SAVED_FILTER_COLUMNS)
		.single();
	if (error) return savedFilterWriteError(error);

	return json(
		{ filter: presentSavedFilter(data, canShare) },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
