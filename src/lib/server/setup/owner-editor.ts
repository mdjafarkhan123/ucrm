import { json, type RequestEvent } from '@sveltejs/kit';
import type { z } from 'zod';
import { setupEditorFieldErrors } from '$lib/server/validation/setup-editor.schema';

// Shared by Jafar's setup editor routes (client onboarding A4).

export async function readJsonBody(event: RequestEvent) {
	try {
		return { body: (await event.request.json()) as unknown };
	} catch {
		return { response: json({ error: 'Request body must be valid JSON.' }, { status: 400 }) };
	}
}

export function invalidSetupDraft(error: z.ZodError, list: 'stages' | 'items' = 'stages') {
	const fieldErrors = setupEditorFieldErrors(error);
	const fallback = list === 'stages' ? 'Please review the stages.' : 'Please review the questions.';
	return json({ error: fieldErrors[list] ?? fallback, field_errors: fieldErrors }, { status: 422 });
}

/**
 * The commands raise plain-English messages: P0002 for a draft or stage that is gone, and constraint codes
 * for a refused change, such as removing a stage that holds built-in questions.
 */
export function setupEditorCommandError(
	error: { code?: string; message: string },
	done: string
): Response {
	if (error.code === 'P0002') return json({ error: error.message }, { status: 404 });
	if (error.code && ['23503', '23505', '23514'].includes(error.code))
		return json({ error: error.message }, { status: 409 });
	console.error(`The setup draft could not be ${done}.`, error);
	return json({ error: `The setup draft could not be ${done}.` }, { status: 500 });
}

/** A command that found the draft saved again since this tab loaded it. */
export function staleSetupDraft(editor: unknown) {
	return json(
		{
			error: 'This draft was changed in another tab. The latest version is shown.',
			reason: 'stale',
			editor
		},
		{ status: 409 }
	);
}
