// The browser side of answering form questions, shared by every customer-facing page that asks them (the
// public request form and the review feedback page). The server re-validates every answer with Zod.

import type { FormQuestionType } from './types';

export function blankAnswer(type: FormQuestionType) {
	if (type === 'dropdown_multi' || type === 'checkbox' || type === 'image_upload')
		return [] as string[];
	if (type === 'yes_no') return null as boolean | null;
	return '';
}

export function isAnswerEmpty(type: FormQuestionType, value: unknown): boolean {
	if (type === 'dropdown_multi' || type === 'checkbox' || type === 'image_upload') {
		return !Array.isArray(value) || value.length === 0;
	}
	if (type === 'yes_no') return value === null || value === undefined;
	return value === '' || value === null || value === undefined;
}
