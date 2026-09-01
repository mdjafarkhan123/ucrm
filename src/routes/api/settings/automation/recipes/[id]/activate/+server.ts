import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import type { Database } from '$lib/database.types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { validateDefinition } from '$lib/server/automation/definition';
import {
	definitionLimits,
	activeRecipesLimit,
	commandErrorResponse,
	staleConflictResponse,
	type RecipeCommandResult
} from '$lib/server/automation/commands';
import {
	activateRecipeSchema,
	automationFieldErrors
} from '$lib/server/validation/automation-authoring.schema';

// Settings → Automation: activate one recipe. `activate` permission is required. Activation freezes an
// IMMUTABLE version from the recipe's own saved draft (never a definition sent by the browser): the route
// reads the current draft under the caller's expected revision, revalidates it at activation strictness
// (>=1 step and >=1 stop) and re-checks referenced email templates, then the atomic command re-locks the
// row, re-checks the revision, enforces the active-recipes ceiling, and appends the frozen version
// (docs/automation-behavior-contract.md §§ Recipe definition and lifecycle, Activation impact review). In
// 6C this is real-but-inert: the version is frozen but nothing runs until the 6D engine exists.

const recipeIdSchema = z.string().uuid();

type EditorRow = {
	status: string;
	draft_definition: unknown;
	draft_revision: number;
};

export const POST: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'activate');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = activateRecipeSchema.safeParse(body);
	if (!parsed.success) return validationError(automationFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;

	// Read the recipe's current draft, tenant-scoped by RLS. A revision mismatch here is the same stale
	// outcome the command would report; short-circuit so a stale actor never triggers validation on content
	// they did not review.
	const { data: recipeRow, error: readError } = await event.locals.supabase
		.from('automation_recipes')
		.select('status, draft_definition, draft_revision')
		.eq('organization_id', organizationId)
		.eq('id', recipeId.data)
		.maybeSingle<EditorRow>();

	if (readError) return json({ error: 'That automation could not be loaded.' }, { status: 500 });
	if (!recipeRow) return json({ error: 'That automation does not exist.' }, { status: 404 });
	if (recipeRow.status === 'archived')
		return json({ error: 'An archived automation is read-only.' }, { status: 409 });
	if (recipeRow.draft_revision !== parsed.data.expected_revision) {
		return staleConflictResponse(getOwnerSupabaseClient(), {
			recipe_id: recipeId.data,
			draft_revision: recipeRow.draft_revision,
			current_revision: recipeRow.draft_revision,
			draft_updated_by: null
		});
	}
	if (recipeRow.draft_definition == null)
		return json({ error: 'This automation has no draft to activate.' }, { status: 422 });

	// Validate at activation strictness against the same catalog + limits the builder uses, and canonicalize
	// server-side. This is the definition that gets frozen; the browser cannot substitute another.
	const validated = validateDefinition(
		recipeRow.draft_definition,
		definitionLimits(check.automation),
		'activation'
	);
	if (!validated.ok) {
		return validationError(
			Object.fromEntries(
				validated.errors.map((issue) => [`definition.${issue.path}`, issue.message])
			)
		);
	}

	const service = getOwnerSupabaseClient();

	try {
		// `p_active_limit` is nullable in the SQL function (null = unlimited; it guards with `is not null`),
		// but Supabase's type generator marks every arg without a DEFAULT as non-nullable.
		const activateArgs: Database['public']['Functions']['activate_automation_recipe_version']['Args'] =
			{
				p_organization_id: organizationId,
				p_actor_user_id: check.auth.user.id,
				p_recipe_id: recipeId.data,
				p_expected_revision: parsed.data.expected_revision,
				p_schema_version: validated.definition.schema_version,
				p_definition: JSON.parse(validated.definitionJson),
				p_definition_hash: validated.hash,
				p_trigger_key: validated.triggerKey,
				p_active_limit: activeRecipesLimit(check.automation) as number,
				p_idempotency_key: parsed.data.idempotency_key
			};
		const { data, error } = await service.rpc('activate_automation_recipe_version', activateArgs);
		if (error) throw error;
		const result = data as unknown as RecipeCommandResult;

		if (result.stale) return staleConflictResponse(service, result);

		return json({
			recipe_id: result.recipe_id,
			status: result.status,
			version_id: result.version_id,
			version_number: result.version_number,
			draft_revision: result.draft_revision
		});
	} catch (error) {
		return commandErrorResponse(error, 'We could not activate that automation. Please try again.');
	}
};
