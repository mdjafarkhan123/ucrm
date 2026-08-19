import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { resolveDateRange } from '$lib/server/pipeline/board';
import { organizationFormatting } from '$lib/server/requests/timezone';

type OutcomeTileRow = {
	outcome_key: 'won' | 'lost';
	closed_count: number;
	value_total: number | null;
};

// The board's own Won/Lost tiles: a fixed rolling 30 days, never the board's own salesperson or date
// controls, because Jobber's tiles aren't either. Its own route rather than folded into `/api/pipeline/
// summary`, because that summary is filtered and cached per filter set, while this is one unfiltered
// answer the board always shows above whatever it is currently filtered to.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const canViewValue = hasPermission(check.access, 'pipeline.view_value');

	const formattingLookup = await organizationFormatting(
		event.locals.supabase,
		check.auth.organization.id
	);
	if (!formattingLookup.ok) return databaseError();
	const { formatting } = formattingLookup;

	const range = resolveDateRange('last_30_days', formatting.timezone);

	const { data, error } = await event.locals.supabase.rpc('pipeline_outcome_tiles', {
		target_organization_id: check.auth.organization.id,
		tile_from: range.from,
		tile_to: range.to
	});
	if (error) return databaseError();

	const rows = (data ?? []) as OutcomeTileRow[];
	const tile = (outcome: 'won' | 'lost') => {
		const row = rows.find((candidate) => candidate.outcome_key === outcome);
		return {
			count: row?.closed_count ?? 0,
			// Present only for a member who may see money. Absent, not zero, for everyone else.
			...(canViewValue ? { value_total: row?.value_total ?? null } : {})
		};
	};

	return json(
		{
			won: tile('won'),
			lost: tile('lost'),
			can_view_value: canViewValue,
			currency_code: formatting.currency_code,
			locale: formatting.locale,
			timezone: formatting.timezone
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
