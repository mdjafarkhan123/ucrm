import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess, type AutomationCapability } from '$lib/server/access/automation';
import { validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	commandErrorResponse,
	staleConflictResponse,
	type RecipeCommandResult
} from '$lib/server/automation/commands';
import {
	lifecycleActionSchema,
	automationFieldErrors,
	type LifecycleActionBody
} from '$lib/server/validation/automation-authoring.schema';

// Settings → Automation: the closed set of recipe state transitions — pause, resume, archive, restore. Each
// is one atomic command guarded by the caller's expected revision and an idempotency key
// (docs/automation-behavior-contract.md § Recipe definition and lifecycle). Capability differs by action:
// pause/resume/archive are `activate` impact commands; restore produces a fresh draft, so it needs `manage`
// (§ Entitlement, permissions, and commands). No definition is sent — these change state only.

const recipeIdSchema = z.string().uuid();

const CAPABILITY_FOR_ACTION: Record<LifecycleActionBody['action'], AutomationCapability> = {
	pause: 'activate',
	resume: 'activate',
	archive: 'activate',
	restore: 'manage'
};

export const POST: RequestHandler = async (event) => {
	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = lifecycleActionSchema.safeParse(body);
	if (!parsed.success) return validationError(automationFieldErrors(parsed.error));

	// Resolve the required capability from the action BEFORE the access gate, so the caller is judged against
	// the permission the specific transition needs (restore = manage; the rest = activate).
	const check = await requireAutomationAccess(event, CAPABILITY_FOR_ACTION[parsed.data.action]);
	if ('response' in check) return check.response;

	const service = getOwnerSupabaseClient();

	try {
		const { data, error } = await service.rpc('set_automation_recipe_lifecycle_state', {
			p_organization_id: check.auth.organization.id,
			p_actor_user_id: check.auth.user.id,
			p_recipe_id: recipeId.data,
			p_expected_revision: parsed.data.expected_revision,
			p_action: parsed.data.action,
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;
		const result = data as unknown as RecipeCommandResult;

		if (result.stale) return staleConflictResponse(service, result);

		return json({
			recipe_id: result.recipe_id,
			status: result.status,
			draft_revision: result.draft_revision
		});
	} catch (error) {
		return commandErrorResponse(error, 'We could not update that automation. Please try again.');
	}
};
