import type { QuoteWriteError } from './api';

// Contractor Settings Part 6D-5b: the browser client for the Quote record-level Automation controls. Every
// call goes through the `/api/quotes/[id]/automation` routes, which own access and the atomic commands; this
// module only shapes requests and surfaces the same `QuoteWriteError` the rest of the quote page already
// understands.

export type RecordEnrollmentState =
	'active' | 'paused' | 'completed' | 'stopped' | 'failed' | string;

export type RecordEnrollment = {
	enrollment_id: string;
	recipe_id: string;
	recipe_name: string;
	version_number: number;
	state: RecordEnrollmentState;
	source: string;
	current_step_index: number;
	next_due_at: string | null;
	customer_messages_sent: number;
	stop_reason: string | null;
	created_at: string;
	updated_at: string;
};

export type EnrollableRecipe = { id: string; name: string };

export type QuoteAutomation = {
	can_control: boolean;
	enrollments: RecordEnrollment[];
	enrollable_recipes: EnrollableRecipe[];
};

export type EnrollmentPreview = {
	eligible: boolean;
	reason: string | null;
	recipe_id?: string;
	recipe_name?: string;
	version_id?: string;
	version_number?: number;
	first_due_at?: string;
	expected_message_count?: number;
	overlap_same_recipe?: number;
	overlap_other_recipes?: number;
};

export type EnrollmentCommandResult = {
	enrollment_id: string;
	state?: string;
	next_due_at?: string;
	current_step_index?: number;
};

export const quoteAutomationKey = (quoteId: string) => ['quotes', 'automation', quoteId] as const;

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as QuoteWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return response.json();
}

export async function fetchQuoteAutomation(quoteId: string): Promise<QuoteAutomation> {
	const response = await fetch(`/api/quotes/${quoteId}/automation`);
	return readOrThrow(response, 'Automation history could not be loaded.');
}

export async function previewEnrollment(
	quoteId: string,
	recipeId: string
): Promise<EnrollmentPreview> {
	const response = await fetch(`/api/quotes/${quoteId}/automation/preview`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ recipe_id: recipeId })
	});
	return readOrThrow(response, 'That preview could not be loaded.');
}

export async function manualEnroll(
	quoteId: string,
	recipeId: string
): Promise<EnrollmentCommandResult> {
	const response = await fetch(`/api/quotes/${quoteId}/automation`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ recipe_id: recipeId, idempotency_key: crypto.randomUUID() })
	});
	return readOrThrow(response, 'We could not enroll that quote.');
}

export type EnrollmentControl =
	| { action: 'pause' }
	| { action: 'resume' }
	| { action: 'skip' }
	| { action: 'stop'; reason?: string };

export async function controlEnrollment(
	quoteId: string,
	enrollmentId: string,
	control: EnrollmentControl
): Promise<EnrollmentCommandResult> {
	const response = await fetch(`/api/quotes/${quoteId}/automation/${enrollmentId}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...control, idempotency_key: crypto.randomUUID() })
	});
	return readOrThrow(response, 'That change could not be applied.');
}
