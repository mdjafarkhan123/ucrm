import { json } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { AutomationAccess } from '$lib/server/access/automation';
import type { DefinitionLimits } from '$lib/server/automation/definition';

// Contractor Settings Part 6C-2: shared server glue for the draft create/save routes. Kept out of the route
// files so both the create and save handlers derive limits and translate a command's error the exact same
// way.

// The two structural limits validateDefinition enforces, projected from the resolved Automation access.
// `null` means unlimited; a non-numeric/absent limit is treated as unlimited so a save is never blocked by a
// missing ceiling (activation, not save, enforces the active-recipes count).
export function definitionLimits(automation: AutomationAccess): DefinitionLimits {
	const asMax = (
		key: 'automation_max_conditions_per_recipe' | 'automation_max_steps_per_recipe'
	) => {
		const limit = automation.limits[key];
		if (limit.is_unlimited || limit.state !== 'numeric') return null;
		return limit.value;
	};
	return {
		maxConditions: asMax('automation_max_conditions_per_recipe'),
		maxSteps: asMax('automation_max_steps_per_recipe')
	};
}

// The effective active-recipes ceiling projected for the activation command: `null` (unlimited) when the
// limit is unlimited or not a concrete number, otherwise the numeric cap. Activation — never save — is where
// this ceiling is enforced (docs/automation-behavior-contract.md § Entitlement: drafts may exceed it).
export function activeRecipesLimit(automation: AutomationAccess): number | null {
	const limit = automation.limits.automation_active_recipes;
	if (limit.is_unlimited || limit.state !== 'numeric') return null;
	return limit.value;
}

// The effective per-enrollment duration ceiling (in days) the manual-enroll command stamps as the
// enrollment's expiry: `null` (no expiry) when the limit is unlimited or not a concrete number, otherwise the
// numeric cap. The engine still stops an enrollment early on any live safety result; this is only the outer
// bound (docs/automation-behavior-contract.md § Record-level Automation controls).
export function enrollmentDurationLimit(automation: AutomationAccess): number | null {
	const limit = automation.limits.automation_max_enrollment_duration_days;
	if (limit.is_unlimited || limit.state !== 'numeric') return null;
	return limit.value;
}

// The shape every recipe draft/lifecycle command returns. On the happy path `stale` is false and the
// command-specific fields are set; on a lost optimistic-lock race `stale` is true and the newer editor/time
// come back so the caller can offer Review/Discard instead of overwriting.
export type RecipeCommandResult = {
	recipe_id: string;
	status?: string;
	draft_revision: number;
	version_id?: string;
	version_number?: number;
	stale?: boolean;
	current_revision?: number;
	draft_updated_at?: string | null;
	draft_updated_by?: string | null;
};

// A stale save/activate/lifecycle result rendered as the same 409 the builder already understands: the newer
// editor's name (resolved best-effort; the timestamp always comes back) and revision, never a blind
// overwrite (docs/automation-behavior-contract.md § Recipe lifecycle). Shared by every recipe write route so
// the conflict shape stays identical across save and lifecycle.
export async function staleConflictResponse(
	serviceClient: SupabaseClient<Database>,
	result: RecipeCommandResult
): Promise<Response> {
	let editorName: string | null = null;
	if (result.draft_updated_by) {
		const { data: profile } = await serviceClient
			.from('profiles')
			.select('full_name')
			.eq('id', result.draft_updated_by)
			.maybeSingle();
		editorName = profile?.full_name ?? null;
	}
	return json(
		{
			error: 'This automation was changed by someone else.',
			stale: true,
			current_revision: result.current_revision ?? null,
			editor_name: editorName,
			updated_at: result.draft_updated_at ?? null
		},
		{ status: 409 }
	);
}

type PgError = { code?: string; message?: string };

function pgError(error: unknown): PgError {
	if (error && typeof error === 'object') {
		const candidate = error as PgError;
		return { code: candidate.code, message: candidate.message };
	}
	return {};
}

// Translate a draft-command failure into an honest response: bad input -> 422, unknown org/recipe -> 404,
// archived/immutability -> 409, everything else -> a generic 500 with the detail logged server-side.
export function commandErrorResponse(error: unknown, fallback: string): Response {
	const { code, message } = pgError(error);
	if (code === '23514') return json({ error: message ?? fallback }, { status: 422 });
	if (code === '23503') return json({ error: message ?? fallback }, { status: 422 });
	if (code === 'P0002') return json({ error: message ?? fallback }, { status: 404 });
	if (code === '23001' || code === '23505')
		return json({ error: message ?? fallback }, { status: 409 });
	console.error(fallback, error);
	return json({ error: fallback }, { status: 500 });
}
