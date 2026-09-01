import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { replaceJobLinesSchema } from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';
import { withCatalogCost } from '$lib/server/quotes/catalog-cost';

// The job's whole scope, replaced in one call — the twin of the quote's own lines route. Nothing here adds up
// a line or a subtotal: `replace_job_line_items` writes the rows and `private.calculate_job` recomputes the
// money, so a job and the quote it came from can never disagree about arithmetic. The reply is only the new
// revision and the line count; the page reloads the job to see its money, which stays behind jobs.view_price.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = replaceJobLinesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// A member who may not see cost never sends one, so the price book fills it in server-side rather than
	// letting a blind save zero out what the job actually costs us. The shared helper reads the quote's name
	// for that column, so the lines wear it for the length of the call and go back to the job's own name.
	const priced = await withCatalogCost(
		event.locals.supabase,
		check.auth.organization.id,
		check.auth.user.id,
		parsed.data.lines.map(({ source_catalog_item_id, ...line }) => ({
			...line,
			catalog_item_id: source_catalog_item_id
		}))
	);
	const lines = priced.map(({ catalog_item_id, ...line }) => ({
		...line,
		source_catalog_item_id: catalog_item_id
	}));

	const { data, error } = await event.locals.supabase.rpc('replace_job_line_items', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_lines: lines
	});

	if (error) return updateJobError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
