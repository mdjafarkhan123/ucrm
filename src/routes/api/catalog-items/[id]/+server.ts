import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { catalogItemUpdateSchema } from '$lib/server/validation/quotes.schema';
import { catalogWriteError } from '$lib/server/quotes/errors';
import { catalogSelect } from '$lib/server/quotes/selects';

const NOT_FOUND = 'That price list item could not be found.';

// Nobody reads a single item today except the Settings Price Book edit dialog, which opens this fetch to
// show the last editor and pick up the current `revision` before a stale save can happen at all -- the same
// reason Taxes' own edit view resolves an editor name inline instead of returning a bare user id.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'catalog.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('catalog_items')
		.select(catalogSelect(hasPermission(check.access, 'quotes.view_cost')))
		.eq('organization_id', check.auth.organization.id)
		.eq('id', event.params.id)
		.maybeSingle();

	if (error) return databaseError();
	if (!data) return notFound(NOT_FOUND);

	let editorName: string | null = null;
	if (data.updated_by) {
		const { data: editor } = await event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', data.updated_by)
			.maybeSingle();
		editorName = editor?.full_name ?? null;
	}

	return json(
		{
			item: {
				...data,
				last_editor: data.updated_by ? { name: editorName, at: data.updated_at } : null
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Editing changes what the next line starts from and nothing that was already written down. Archiving is
// this same call with `archived`, never a delete: old request lines and quote copies still name the item
// they came from, and the write function refuses to start a new line from an archived one.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'catalog.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = catalogItemUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { archived, ...fields } = parsed.data;
	const changes: Record<string, unknown> = {};
	for (const [key, value] of Object.entries(fields)) {
		if (value !== undefined) changes[key] = value;
	}
	if (archived !== undefined) changes.archived_at = archived ? new Date().toISOString() : null;

	const { data, error } = await event.locals.supabase
		.from('catalog_items')
		.update(changes)
		.eq('organization_id', check.auth.organization.id)
		.eq('id', event.params.id)
		.select(catalogSelect(hasPermission(check.access, 'quotes.view_cost')))
		.maybeSingle();

	if (error) return catalogWriteError(error);
	if (!data) return notFound(NOT_FOUND);
	return json({ item: data }, { headers: NO_STORE_HEADERS });
};
