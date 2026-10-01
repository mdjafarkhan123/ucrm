import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { updateSavedFilterSchema } from '$lib/server/validation/pipeline.schema';
import {
	SAVED_FILTER_COLUMNS,
	canShareFilters,
	presentSavedFilter,
	savedFilterMissing,
	savedFilterWriteError
} from '$lib/server/pipeline/saved-filters';
import { savedFilterQuery } from '$lib/pipeline/filters';

// Renames a saved filter, or replaces what it shows with the board's current controls. The policies only
// let the caller reach their own filters and, for an administrator, the shared ones; any other id — a
// teammate's personal filter, another organization's — matches no row and reads as not found.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateSavedFilterSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const change: { name?: string; query?: string } = {};
	if (parsed.data.name !== undefined) change.name = parsed.data.name;
	if (parsed.data.filters !== undefined) {
		const query = savedFilterQuery(parsed.data.filters);
		if (!query) return validationError({ form: 'Change at least one filter before saving.' });
		change.query = query;
	}

	const { data, error } = await event.locals.supabase
		.from('pipeline_saved_filters')
		.update(change)
		.eq('id', event.params.id)
		.eq('organization_id', check.auth.organization.id)
		.select(SAVED_FILTER_COLUMNS);
	if (error) return savedFilterWriteError(error);

	const row = data?.[0];
	if (!row) return savedFilterMissing();

	return json(
		{ filter: presentSavedFilter(row, canShareFilters(check.auth)) },
		{ headers: NO_STORE_HEADERS }
	);
};

export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('pipeline_saved_filters')
		.delete()
		.eq('id', event.params.id)
		.eq('organization_id', check.auth.organization.id)
		.select('id');
	if (error) return databaseError();
	if (!data?.length) return savedFilterMissing();

	return new Response(null, { status: 204, headers: NO_STORE_HEADERS });
};
