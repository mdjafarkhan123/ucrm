// Human labels and grouping for the builder's question palette. Kept apart from types.ts so that file stays
// the pure content-shape contract; this is display metadata the builder and preview share. Order here is the
// order the "Add question" palette shows, matching Jobber's builder (jobber-02 § 4.4).

import type { FormQuestionType } from './types';

export const FORM_QUESTION_TYPE_LABELS: Record<FormQuestionType, string> = {
	short_text: 'Short answer',
	long_text: 'Long answer',
	dropdown: 'Dropdown',
	dropdown_multi: 'Dropdown (choose many)',
	radio: 'Single choice',
	checkbox: 'Checkboxes',
	number: 'Number',
	yes_no: 'Yes / No',
	image_upload: 'Photo upload'
};

// A one-line hint under each palette button so a non-technical owner knows what the question does.
export const FORM_QUESTION_TYPE_HINTS: Record<FormQuestionType, string> = {
	short_text: 'A single line of text',
	long_text: 'A longer paragraph',
	dropdown: 'Pick one from a list',
	dropdown_multi: 'Pick several from a list',
	radio: 'Choose one option',
	checkbox: 'Tick any that apply',
	number: 'A number only',
	yes_no: 'A simple yes or no',
	image_upload: 'Let customers attach photos'
};
