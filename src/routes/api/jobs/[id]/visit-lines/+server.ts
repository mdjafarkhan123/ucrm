import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Up to the hundred `job_visit_lines` itself allows — the same ceiling one invoice's claims carry, so a
// selection this route answers is always one a bill could actually be made from.
const querySchema = z.object({
	visits: z
		.string()
		.transform((value) => value.split(',').filter(Boolean))
		.pipe(
			z
				.array(z.string().uuid('Those visits could not be read.'))
				.min(1, 'Choose at least one visit.')
				.max(100, 'That is too many visits to read at once.')
		)
});

// What each of these visits actually bills: its own lines if it has been customised, the job's lines if it
// has not. Behind the visit editor (one visit) and the invoice composer seeding a bill from visits already
// chosen (several) — one call either way, because a per-visit round trip would be a waterfall.
//
// `job_visit_lines` is definer and applies jobs.view, jobs.view_price and jobs.view_cost for itself, so a
// reader who may see less simply gets less rather than a second gate here.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const parsed = querySchema.safeParse(Object.fromEntries(event.url.searchParams.entries()));
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('job_visit_lines', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_visit_ids: parsed.data.visits
	});
	if (error) return databaseError();

	return json(data ?? { visits: [] }, { headers: PRIVATE_READ_HEADERS });
};
