import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Settings → Automation detail, Versions tab: the frozen activation history of ONE recipe. `view`-gated and
// tenant-scoped by RLS. A recipe accumulates one immutable version per activation, so this is bounded per
// recipe — ordered newest-first and hard-capped — and returns each version's definition so the tab can show
// what changed between them (docs/automation-behavior-contract.md § Recipe detail: Version comparison). The
// query stays off until the tab is revealed, per the prefetch-on-reveal rule.

const recipeIdSchema = z.string().uuid();
const MAX_VERSIONS = 50;

type VersionRow = {
	id: string;
	version_number: number;
	schema_version: number;
	trigger_key: string;
	definition: unknown;
	activated_at: string;
	activated_by: string | null;
};

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	const organizationId = check.auth.organization.id;

	const { data, error } = await event.locals.supabase
		.from('automation_recipe_versions')
		.select(
			'id, version_number, schema_version, trigger_key, definition, activated_at, activated_by'
		)
		.eq('organization_id', organizationId)
		.eq('recipe_id', recipeId.data)
		.order('version_number', { ascending: false })
		.limit(MAX_VERSIONS)
		.returns<VersionRow[]>();
	if (error) return databaseError();

	const rows = data ?? [];

	// Resolve the activators' names once, on the service client, so the tab can say who activated each version
	// without the caller needing to read co-members' profiles directly.
	const activatorIds = [
		...new Set(rows.map((row) => row.activated_by).filter((id): id is string => !!id))
	];
	const nameById = new Map<string, string>();
	if (activatorIds.length > 0) {
		const { data: profiles } = await getOwnerSupabaseClient()
			.from('profiles')
			.select('id, full_name')
			.in('id', activatorIds);
		for (const profile of profiles ?? []) {
			if (profile.full_name) nameById.set(profile.id, profile.full_name);
		}
	}

	const versions = rows.map((row) => ({
		id: row.id,
		version_number: row.version_number,
		schema_version: row.schema_version,
		trigger_key: row.trigger_key,
		definition: row.definition,
		activated_at: row.activated_at,
		activated_by_name: row.activated_by ? (nameById.get(row.activated_by) ?? null) : null
	}));

	return json({ versions }, { headers: PRIVATE_READ_HEADERS });
};
