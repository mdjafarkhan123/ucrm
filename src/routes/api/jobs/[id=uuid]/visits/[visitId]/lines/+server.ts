import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { replaceVisitLinesSchema } from '$lib/server/validation/jobs.schema';
import { scheduleVisitError } from '$lib/server/jobs/errors';
import { withCatalogCost } from '$lib/server/quotes/catalog-cost';

// One visit's own pricing, replaced in one call — the twin of the job's own lines route, one level down.
// `replace_job_visit_line_items` checks jobs.edit, refuses a job that is not billed per visit, a completed or
// already-invoiced visit and a stale revision, and hands back the visit's new revision for the next save.
//
// An empty list is a real instruction here, not an empty save: it clears the visit's own set and puts it back
// on the job's lines, which is the only way back.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = replaceVisitLinesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// The same reason the job's lines route does this: a member who may not see cost never sends one, and a
	// blind save must not zero out what the work actually costs us. The price book fills it in server-side.
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

	const { data, error } = await event.locals.supabase.rpc('replace_job_visit_line_items', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_visit_id: event.params.visitId,
		expected_revision: parsed.data.expected_revision,
		new_lines: lines
	});

	if (error) return scheduleVisitError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
