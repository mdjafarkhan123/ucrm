// Settings → Automation builder: the client state for authoring one recipe draft (Part 6C-2b). TanStack
// Query owns cache reads (the editor load); this module only shapes the request/response
// and the write calls the builder makes. Every write carries a fresh idempotency key so a retried submit is
// replayed, never duplicated, and a stale save surfaces as StaleDraftError so the builder can offer
// Review/Discard without ever overwriting a newer editor's work.

import type { AuthoredDefinition } from '$lib/automation/authoring';
import type { RecipeSource, RecipeStatus } from '$lib/settings/automation-recipes';

// The row the editor read (GET /recipes/[id]/editor) projects — everything the builder form needs, nothing
// more. `draft_definition` is the stored AuthoredDefinition; `draft_revision` is the optimistic-lock token
// the next save must echo back.
export type EditorRecipe = {
	id: string;
	name: string;
	status: RecipeStatus;
	source: RecipeSource;
	preset_key: string | null;
	preset_version: number | null;
	draft_definition: AuthoredDefinition;
	draft_revision: number;
	draft_updated_at: string | null;
};

export type DraftCommandResult = { recipe_id: string; draft_revision: number };

// A save that lost the optimistic-lock race. Not an error the user caused — someone else saved first — so the
// builder shows who and when and offers Review (reload their version) or Discard, never a blind overwrite.
export class StaleDraftError extends Error {
	readonly stale = true;
	constructor(
		readonly currentRevision: number | null,
		readonly editorName: string | null,
		readonly updatedAt: string | null
	) {
		super('This automation was changed by someone else.');
		this.name = 'StaleDraftError';
	}
}

export const automationEditorKey = (recipeId: string) =>
	['settings', 'automation', 'editor', recipeId] as const;

async function readError(response: Response, fallback: string): Promise<string> {
	try {
		const body = (await response.json()) as { error?: string };
		return body.error ?? fallback;
	} catch {
		return fallback;
	}
}

export async function fetchRecipeEditor(recipeId: string): Promise<EditorRecipe> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/editor`);
	if (!response.ok)
		throw new Error(await readError(response, 'That automation could not be loaded.'));
	return (await response.json()) as EditorRecipe;
}

export type CreateDraftInput = {
	name: string;
	source: RecipeSource;
	presetKey?: string | null;
	presetVersion?: number | null;
	definition: AuthoredDefinition;
	idempotencyKey: string;
};

export async function createRecipeDraft(input: CreateDraftInput): Promise<DraftCommandResult> {
	const response = await fetch('/api/settings/automation/recipes', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			name: input.name,
			source: input.source,
			preset_key: input.source === 'preset' ? (input.presetKey ?? null) : null,
			preset_version: input.source === 'preset' ? (input.presetVersion ?? null) : null,
			idempotency_key: input.idempotencyKey,
			definition: input.definition
		})
	});
	if (!response.ok)
		throw new Error(await readError(response, 'We could not create that automation.'));
	return (await response.json()) as DraftCommandResult;
}

export type SaveDraftInput = {
	recipeId: string;
	name: string;
	expectedRevision: number;
	definition: AuthoredDefinition;
	idempotencyKey: string;
};

export async function saveRecipeDraft(input: SaveDraftInput): Promise<DraftCommandResult> {
	const response = await fetch(`/api/settings/automation/recipes/${input.recipeId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			expected_revision: input.expectedRevision,
			name: input.name,
			idempotency_key: input.idempotencyKey,
			definition: input.definition
		})
	});

	if (response.status === 409) {
		const body = (await response.json()) as {
			current_revision?: number | null;
			editor_name?: string | null;
			updated_at?: string | null;
		};
		throw new StaleDraftError(
			body.current_revision ?? null,
			body.editor_name ?? null,
			body.updated_at ?? null
		);
	}
	if (!response.ok)
		throw new Error(await readError(response, 'We could not save that automation.'));
	return (await response.json()) as DraftCommandResult;
}
