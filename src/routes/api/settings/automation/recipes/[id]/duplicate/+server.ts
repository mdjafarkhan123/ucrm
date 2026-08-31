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
	duplicateRecipeSchema,
	automationFieldErrors
} from '$lib/server/validation/automation-authoring.schema';

// Settings → Automation: duplicate one recipe into a brand-new independent draft. `manage` is required (it
// authors a new draft). The atomic command copies the source's current definition, guards the source
// revision so the copy reflects what the actor saw, and starts the new recipe in Draft — so it never counts
// against the active-recipes limit (docs/automation-behavior-contract.md § Recipe definition and lifecycle).

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

	const parsed = duplicateRecipeSchema.safeParse(body);
	if (!parsed.success) return validationError(automationFieldErrors(parsed.error));

	const service = getOwnerSupabaseClient();

	try {
		const { data, error } = await service.rpc('duplicate_automation_recipe', {
			p_organization_id: check.auth.organization.id,
			p_actor_user_id: check.auth.user.id,
			p_recipe_id: recipeId.data,
			p_expected_revision: parsed.data.expected_revision,
			p_name: parsed.data.name,
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;
		const result = data as unknown as RecipeCommandResult;

		if (result.stale) return staleConflictResponse(service, result);

		return json(
			{ recipe_id: result.recipe_id, status: result.status, draft_revision: result.draft_revision },
			{ status: 201 }
		);
	} catch (error) {
		return commandErrorResponse(error, 'We could not duplicate that automation. Please try again.');
	}
};
