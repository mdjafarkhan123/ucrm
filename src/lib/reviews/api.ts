import { httpError, type HttpError } from '$lib/http-error';
import type { ReviewSettingsInput, ReviewSettingsView } from './settings';

// Google review campaign Part 1: the browser side of the review setup.

export const reviewSettingsKey = ['reviews', 'settings'] as const;

export type ReviewSettingsSaveError = HttpError & { fieldErrors: Record<string, string> };

export async function fetchReviewSettings(): Promise<ReviewSettingsView> {
	const response = await fetch('/api/reviews/settings');
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw httpError(response, result.error ?? 'Review settings could not be loaded.');
	}
	return response.json();
}

export async function saveReviewSettings(input: ReviewSettingsInput): Promise<ReviewSettingsView> {
	const response = await fetch('/api/reviews/settings', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await response
		.json()
		.catch(() => ({}) as { error?: string; field_errors?: Record<string, string> });
	if (!response.ok) {
		const error = httpError(
			response,
			result.error ?? 'Review settings could not be saved.'
		) as ReviewSettingsSaveError;
		error.fieldErrors = result.field_errors ?? {};
		throw error;
	}
	return result as ReviewSettingsView;
}
