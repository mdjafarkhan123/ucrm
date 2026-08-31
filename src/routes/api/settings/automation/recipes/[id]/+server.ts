import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { validateDefinition } from '$lib/server/automation/definition';
import {
	definitionLimits,
	commandErrorResponse,
	staleConflictResponse,
	type RecipeCommandResult
} from '$lib/server/automation/commands';
import {
	saveRecipeDraftSchema,
	automationFieldErrors
} from '$lib/server/validation/automation-authoring.schema';

// Settings → Automation builder: save one recipe's draft. `manage` is required. The definition is validated
// against the catalog and limits, any referenced email templates must belong to this organization, and the
// atomic command enforces organization ownership plus the caller-supplied revision. A stale revision is a
// normal outcome, not an error: the newer editor and time come back with a 409 so the builder can offer
// review or discard, never a blind overwrite (docs/automation-behavior-contract.md § Recipe lifecycle).

const recipeIdSchema = z.string().uuid();

// Settings → Automation detail: the view-only read behind /settings/automation/[id]. `view` is enough —
// reading an automation is not managing it. Returns the header facts, the sequence Overview renders, and the
// `draft_revision` optimistic-lock token every later action must echo. Bounded: one recipe row, at most one
// frozen version, and one profile lookup for the editor's name (docs/automation-behavior-contract.md
// § Recipe detail). Definitions are returned here on purpose — the detail page needs to show the sequence.
type RecipeDetailRow = {
	id: string;
	name: string;
	status: string;
	source: 'preset' | 'custom';
	preset_key: string | null;
	preset_version: number | null;
	active_trigger_key: string | null;
	draft_definition: unknown;
	draft_revision: number;
	draft_updated_at: string | null;
	draft_updated_by: string | null;
	current_version_id: string | null;
	created_at: string;
	updated_at: string;
};

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	const { data: recipe, error } = await supabase
		.from('automation_recipes')
		.select(
			'id, name, status, source, preset_key, preset_version, active_trigger_key, draft_definition, draft_revision, draft_updated_at, draft_updated_by, current_version_id, created_at, updated_at'
		)
		.eq('organization_id', organizationId)
		.eq('id', recipeId.data)
		.maybeSingle<RecipeDetailRow>();
	if (error) return databaseError();
	if (!recipe) return json({ error: 'That automation does not exist.' }, { status: 404 });

	// The frozen active version, when there is one, gives the header its version number and — for an active or
	// paused recipe with no outstanding draft — the immutable definition Overview shows.
	let activeVersion: { version_number: number; activated_at: string; definition: unknown } | null =
		null;
	if (recipe.current_version_id) {
		const { data: version, error: versionError } = await supabase
			.from('automation_recipe_versions')
			.select('version_number, activated_at, definition')
			.eq('organization_id', organizationId)
			.eq('id', recipe.current_version_id)
			.maybeSingle<{ version_number: number; activated_at: string; definition: unknown }>();
		if (versionError) return databaseError();
		activeVersion = version ?? null;
	}

	// The last editor's name, resolved on the service client exactly like the stale-conflict path so it does
	// not depend on the caller also being allowed to read co-members' profiles.
	let lastEditorName: string | null = null;
	if (recipe.draft_updated_by) {
		const { data: profile } = await getOwnerSupabaseClient()
			.from('profiles')
			.select('full_name')
			.eq('id', recipe.draft_updated_by)
			.maybeSingle();
		lastEditorName = profile?.full_name ?? null;
	}

	// Overview renders the outstanding draft when there is one, otherwise the frozen active version; an active
	// recipe's definition is immutable until an Edit opens a fresh draft.
	const displayDefinition = recipe.draft_definition ?? activeVersion?.definition ?? null;

	return json(
		{
			id: recipe.id,
			name: recipe.name,
			status: recipe.status,
			source: recipe.source,
			preset_key: recipe.preset_key,
			preset_version: recipe.preset_version,
			trigger_key: recipe.active_trigger_key,
			draft_revision: recipe.draft_revision,
			draft_updated_at: recipe.draft_updated_at,
			last_editor_name: lastEditorName,
			has_draft: recipe.draft_definition != null,
			display_definition: displayDefinition,
			active_version: activeVersion
				? {
						version_number: activeVersion.version_number,
						activated_at: activeVersion.activated_at
					}
				: null,
			created_at: recipe.created_at,
			updated_at: recipe.updated_at
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const PATCH: RequestHandler = async (event) => {
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

	const parsed = saveRecipeDraftSchema.safeParse(body);
	if (!parsed.success) return validationError(automationFieldErrors(parsed.error));

	const validated = validateDefinition(
		parsed.data.definition,
		definitionLimits(check.automation),
		'draft'
	);
	if (!validated.ok) {
		return validationError(
			Object.fromEntries(
				validated.errors.map((issue) => [`definition.${issue.path}`, issue.message])
			)
		);
	}

	const organizationId = check.auth.organization.id;
	const service = getOwnerSupabaseClient();

	try {
		const { data, error } = await service.rpc('save_automation_recipe_draft', {
			p_organization_id: organizationId,
			p_actor_user_id: check.auth.user.id,
			p_recipe_id: recipeId.data,
			p_expected_revision: parsed.data.expected_revision,
			p_name: parsed.data.name,
			p_definition: JSON.parse(validated.definitionJson),
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;
		const result = data as unknown as RecipeCommandResult;

		if (result.stale) return staleConflictResponse(service, result);

		return json({ recipe_id: result.recipe_id, draft_revision: result.draft_revision });
	} catch (error) {
		return commandErrorResponse(error, 'We could not save that automation. Please try again.');
	}
};
