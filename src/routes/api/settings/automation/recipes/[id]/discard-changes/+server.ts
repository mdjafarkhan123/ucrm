import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	commandErrorResponse,
	staleConflictResponse,
	type RecipeCommandResult
} from '$lib/server/automation/commands';
import {
	discardRecipeChangesSchema,
	automationFieldErrors
} from '$lib/server/validation/automation-authoring.schema';

// Settings → Automation detail: throw away an active or paused automation's unpublished edits (Zapier's
// "Discard draft", HubSpot's "Revert changes"). `manage` is required, the same as saving a draft. The draft is
// overwritten with the recipe's OWN live version, read here — never a definition from the browser — through
// the existing revision-checked save command, so a concurrent edit is a normal stale conflict, not an overwrite.
// Customers and enrollments are untouched: they only ever run frozen versions.

const recipeIdSchema = z.string().uuid();

export const POST: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'manage');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = discardRecipeChangesSchema.safeParse(body);
	if (!parsed.success) return validationError(automationFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	const { data: recipe, error: readError } = await event.locals.supabase
		.from('automation_recipes')
		.select('name, status, current_version_id')
		.eq('organization_id', organizationId)
		.eq('id', recipeId.data)
		.maybeSingle();
	if (readError) return json({ error: 'That automation could not be loaded.' }, { status: 500 });
	if (!recipe) return json({ error: 'That automation does not exist.' }, { status: 404 });
	if ((recipe.status !== 'active' && recipe.status !== 'paused') || !recipe.current_version_id)
		return json({ error: 'Only a live automation has changes to discard.' }, { status: 409 });

	const { data: version, error: versionError } = await event.locals.supabase
		.from('automation_recipe_versions')
		.select('definition')
		.eq('organization_id', organizationId)
		.eq('id', recipe.current_version_id)
		.maybeSingle();
	if (versionError || !version)
		return json({ error: 'That automation could not be loaded.' }, { status: 500 });

	const service = getOwnerSupabaseClient();
	try {
		const { data, error } = await service.rpc('save_automation_recipe_draft', {
			p_organization_id: organizationId,
			p_actor_user_id: check.auth.user.id,
			p_recipe_id: recipeId.data,
			p_expected_revision: parsed.data.expected_revision,
			p_name: recipe.name,
			p_definition: version.definition,
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;
		const result = data as unknown as RecipeCommandResult;

		if (result.stale) return staleConflictResponse(service, result);

		return json({ recipe_id: result.recipe_id, draft_revision: result.draft_revision });
	} catch (error) {
		return commandErrorResponse(error, 'We could not discard those changes. Please try again.');
	}
};
