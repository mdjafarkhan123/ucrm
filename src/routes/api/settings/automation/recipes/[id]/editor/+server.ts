import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

// Settings → Automation builder: the bounded editor read for one recipe. `manage` is required (this is the
// edit surface; the plain detail read in 6C-3 is view-only). It is a single-row lookup by id, tenant-scoped
// by RLS, projecting only what the builder form needs — never a list, event payload, or version stack
// (docs/automation-behavior-contract.md § Query, index, and count).

const recipeIdSchema = z.string().uuid();

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'manage');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	const { data, error } = await event.locals.supabase
		.from('automation_recipes')
		.select(
			'id, name, status, source, preset_key, preset_version, draft_definition, draft_revision, draft_updated_at'
		)
		.eq('organization_id', check.auth.organization.id)
		.eq('id', recipeId.data)
		.maybeSingle();

	if (error) return json({ error: 'That automation could not be loaded.' }, { status: 500 });
	if (!data) return json({ error: 'That automation does not exist.' }, { status: 404 });

	return json(data, { headers: PRIVATE_READ_HEADERS });
};
