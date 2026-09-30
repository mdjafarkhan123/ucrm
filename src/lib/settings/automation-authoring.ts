import { httpError } from '$lib/http-error';
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

// A save the server refused because of what was in it. `stepErrors` maps a step's position to its message
// so the builder can mark that step; the error's own message is the first problem in plain words, so a
// problem with the whole sequence (too many messages) still reads clearly in a toast.
export class RecipeValidationError extends Error {
	readonly status = 422;
	constructor(
		message: string,
		readonly stepErrors: Record<number, string>
	) {
		super(message);
		this.name = 'RecipeValidationError';
	}
}

async function readError(response: Response, fallback: string): Promise<Error> {
	let body: { error?: string; field_errors?: Record<string, string> } = {};
	try {
		body = (await response.json()) as typeof body;
	} catch {
		return httpError(response, fallback);
	}
	const fieldErrors = Object.entries(body.field_errors ?? {});
	if (response.status === 422 && fieldErrors.length > 0) {
		const stepErrors: Record<number, string> = {};
		for (const [path, message] of fieldErrors) {
			const match = /^definition\.steps\.(\d+)(\.|$)/.exec(path);
			if (match && stepErrors[Number(match[1])] === undefined)
				stepErrors[Number(match[1])] = message;
		}
		return new RecipeValidationError(fieldErrors[0][1], stepErrors);
	}
	return httpError(response, body.error ?? fallback);
}

export async function fetchRecipeEditor(recipeId: string): Promise<EditorRecipe> {
	const response = await fetch(`/api/settings/automation/recipes/${recipeId}/editor`);
	if (!response.ok) throw await readError(response, 'That automation could not be loaded.');
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
	if (!response.ok) throw await readError(response, 'We could not create that automation.');
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
	if (!response.ok) throw await readError(response, 'We could not save that automation.');
	return (await response.json()) as DraftCommandResult;
}

// Stage 7: the Send SMS action editor's live segment/cost estimate. Never throws on a normal "not ready yet"
// outcome (no sender, no published rate) — those come back as {ready: false, reason}; only a genuine request
// failure throws. Mirrors estimateSmsReply (src/lib/communications/inbox.ts).
export type AutomationSmsEstimate =
	| {
			ready: true;
			encoding: string;
			segment_count: number;
			cost_minor: number;
			currency: string;
			sender_phone: string;
	  }
	| { ready: false; reason: string };

export async function estimateAutomationSms(body: string): Promise<AutomationSmsEstimate> {
	const response = await fetch('/api/settings/automation/sms-estimate', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ body })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'This estimate could not be loaded.');
	return result as AutomationSmsEstimate;
}

// The Send SMS action editor's optional "pin a number" picker: only numbers eligible to send right now.
export type AutomationSmsSender = {
	id: string;
	phone_number: string;
	display_name: string | null;
	is_default_sender: boolean;
};

// Google review Part 4B: the review request step's readiness line.
export type AutomationReviewReadiness = {
	sms_ready: boolean;
	email_ready: boolean;
	has_google_link: boolean;
};

export const automationReviewReadinessKey = ['settings', 'automation', 'review-readiness'] as const;

export async function fetchAutomationReviewReadiness(): Promise<AutomationReviewReadiness> {
	const response = await fetch('/api/settings/automation/review-readiness');
	if (!response.ok)
		throw await readError(response, 'Whether review requests can send could not be checked.');
	return response.json();
}

export async function fetchAutomationSmsSenders(): Promise<AutomationSmsSender[]> {
	const response = await fetch('/api/settings/automation/sms-senders');
	if (!response.ok) throw await readError(response, 'The SMS numbers could not be loaded.');
	const body = (await response.json()) as { senders: AutomationSmsSender[] };
	return body.senders;
}
