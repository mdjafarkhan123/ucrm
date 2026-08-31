// Settings → Automation detail: the client state for reading one recipe and running its lifecycle actions
// (Part 6C-3b). TanStack Query owns the cache reads (detail, versions, activation preview); this module only
// shapes the request/response and the write calls the detail page makes. Every write carries a FRESH
// idempotency key so a retried submit is replayed, never repeated, and a lost optimistic-lock race surfaces
// as StaleDraftError so the page can offer Review/Discard instead of ever overwriting a newer editor's work
// (docs/automation-behavior-contract.md § Recipe definition and lifecycle).

import type { AuthoredDefinition } from '$lib/automation/authoring';
import type { AutomationLimit } from '$lib/settings/automation';
import { StaleDraftError } from '$lib/settings/automation-authoring';
import type { RecipeSource, RecipeStatus } from '$lib/settings/automation-recipes';

export { StaleDraftError };

// The view-only detail read (GET /recipes/[id]). `display_definition` is the sequence Overview renders — the
// outstanding draft when there is one, otherwise the frozen active version. `draft_revision` is the
// optimistic-lock token every lifecycle action must echo back.
export type RecipeDetail = {
	id: string;
	name: string;
	status: RecipeStatus;
	source: RecipeSource;
	preset_key: string | null;
	preset_version: number | null;
	trigger_key: string | null;
	draft_revision: number;
	draft_updated_at: string | null;
	last_editor_name: string | null;
	has_draft: boolean;
	display_definition: AuthoredDefinition | null;
	active_version: { version_number: number; activated_at: string } | null;
	created_at: string;
	updated_at: string;
};

export type RecipeVersion = {
	id: string;
	version_number: number;
	schema_version: number;
	trigger_key: string;
	definition: AuthoredDefinition;
	activated_at: string;
	activated_by_name: string | null;
};

// The impact the activation dialog shows when it opens. `valid` folds every blocking finding AND the
// over-limit check into one gate for the Activate button; `blocking` explains why when it is false.
export type ActivationPreview = {
	recipe_id: string;
	status: RecipeStatus;
	draft_revision: number;
	already_active: boolean;
	valid: boolean;
	blocking: string[];
	summary: {
		trigger_label: string;
		max_messages: number;
		step_count: number;
		condition_count: number;
		stop_count: number;
	} | null;
	active_recipes: { limit: number | null; count: number; over_limit: boolean };
	effective_limits: {
		automation_max_customer_messages_per_enrollment: AutomationLimit;
		automation_min_customer_message_spacing_minutes: AutomationLimit;
		automation_max_delay_days: AutomationLimit;
		automation_max_enrollment_duration_days: AutomationLimit;
	};
};

export type LifecycleAction = 'pause' | 'resume' | 'archive' | 'restore';

export type LifecycleResult = { recipe_id: string; status: RecipeStatus; draft_revision: number };
export type ActivateResult = {
	recipe_id: string;
	status: RecipeStatus;
	version_id: string;
	version_number: number;
	draft_revision: number;
};
export type DuplicateResult = { recipe_id: string; draft_revision: number };

// One entry of a recipe's run history (6D-4). A safe projection of one (event, recipe) decision: either the
// automation enrolled a subject, or the plain reason it did not. Never carries the enrollment context
// snapshot, the event payload, a message body, or any worker state.
export type RecipeHistoryOutcome =
	| 'enrolled'
	| 'already_enrolled'
	| 'before_activation'
	| 'not_entitled'
	| 'authority_blocked'
	| 'subject_gone'
	| 'condition_failed'
	| 'condition_unavailable';

export type RecipeHistoryEntry = {
	id: string;
	happened_at: string;
	outcome: RecipeHistoryOutcome;
	detail: string | null;
	subject_type: string;
	subject_id: string;
	// Present only for enrolled rows: the current state of the enrollment this decision started, and how many
	// customer messages it has sent so far.
	enrollment_state: 'active' | 'paused' | 'completed' | 'stopped' | 'failed' | null;
	customer_messages_sent: number | null;
};

export type RecipeHistoryPage = {
	entries: RecipeHistoryEntry[];
	next_cursor: string | null;
};

export const automationRecipeDetailKey = (recipeId: string) =>
	['settings', 'automation', 'recipe', recipeId] as const;
export const automationRecipeVersionsKey = (recipeId: string) =>
	['settings', 'automation', 'recipe', recipeId, 'versions'] as const;
export const automationRecipeHistoryKey = (recipeId: string) =>
	['settings', 'automation', 'recipe', recipeId, 'history'] as const;
export const automationActivationPreviewKey = (recipeId: string) =>
	['settings', 'automation', 'recipe', recipeId, 'activation-preview'] as const;

async function readError(response: Response, fallback: string): Promise<string> {
	try {
		const body = (await response.json()) as { error?: string };
		return body.error ?? fallback;
	} catch {
		return fallback;
	}
}

// A 409 from any lifecycle write is a lost optimistic-lock race, shaped exactly like the builder's save
// conflict. Translate it once so every caller can offer Review/Discard without a blind overwrite.
async function throwIfStale(response: Response): Promise<void> {
	if (response.status !== 409) return;
	const body = (await response.json()) as {
		stale?: boolean;
		current_revision?: number | null;
		editor_name?: string | null;
		updated_at?: string | null;
		error?: string;
	};
	// A 409 that is not the stale-editor shape (e.g. over-limit, invalid transition) carries its own message.
	if (body.stale !== true) throw new Error(body.error ?? 'That automation could not be updated.');
	throw new StaleDraftError(
		body.current_revision ?? null,
		body.editor_name ?? null,
		body.updated_at ?? null
	);
}

export async function fetchRecipeDetail(recipeId: string): Promise<RecipeDetail> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}`);
	if (!response.ok)
		throw new Error(await readError(response, 'That automation could not be loaded.'));
	return (await response.json()) as RecipeDetail;
}

export async function fetchRecipeVersions(recipeId: string): Promise<RecipeVersion[]> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/versions`);
	if (!response.ok)
		throw new Error(await readError(response, 'This automation’s history could not be loaded.'));
	const body = (await response.json()) as { versions: RecipeVersion[] };
	return body.versions;
}

export async function fetchRecipeHistory(
	recipeId: string,
	pageParam?: string
): Promise<RecipeHistoryPage> {
	const qs = pageParam ? `?cursor=${encodeURIComponent(pageParam)}` : '';
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/history${qs}`);
	if (!response.ok)
		throw new Error(await readError(response, 'This automation’s history could not be loaded.'));
	return (await response.json()) as RecipeHistoryPage;
}

export async function fetchActivationPreview(recipeId: string): Promise<ActivationPreview> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/activation-preview`);
	if (!response.ok)
		throw new Error(
			await readError(response, 'We could not check this automation for activation.')
		);
	return (await response.json()) as ActivationPreview;
}

export async function activateRecipe(
	recipeId: string,
	expectedRevision: number
): Promise<ActivateResult> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/activate`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			expected_revision: expectedRevision,
			idempotency_key: crypto.randomUUID()
		})
	});
	await throwIfStale(response);
	if (!response.ok)
		throw new Error(await readError(response, 'We could not activate that automation.'));
	return (await response.json()) as ActivateResult;
}

export async function setRecipeLifecycle(
	recipeId: string,
	action: LifecycleAction,
	expectedRevision: number
): Promise<LifecycleResult> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/lifecycle`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			action,
			expected_revision: expectedRevision,
			idempotency_key: crypto.randomUUID()
		})
	});
	await throwIfStale(response);
	if (!response.ok)
		throw new Error(await readError(response, 'We could not update that automation.'));
	return (await response.json()) as LifecycleResult;
}

export async function duplicateRecipe(
	recipeId: string,
	name: string,
	expectedRevision: number
): Promise<DuplicateResult> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/duplicate`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			name,
			expected_revision: expectedRevision,
			idempotency_key: crypto.randomUUID()
		})
	});
	await throwIfStale(response);
	if (!response.ok)
		throw new Error(await readError(response, 'We could not duplicate that automation.'));
	return (await response.json()) as DuplicateResult;
}
