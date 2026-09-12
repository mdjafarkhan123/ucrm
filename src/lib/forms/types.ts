// Request/booking form builder — shared shape and limits (Contractor Settings Part 4B-1).
//
// This is the single source of truth for the content document stored in `form_versions.content` and the
// caps the builder and the Zod validator both enforce. The database only guards that content is a json
// object within a gross size bound (see 20260912120000_contractor_settings_forms_builder_content.sql); the
// real per-field shape is validated by `forms.schema.ts` in the /api layer before any write.
//
// Question types mirror Jobber's builder observed live (jobber-02-requests-leads.md § 4.4): short/long
// answer, single- and multi-select dropdown, radio, checkbox, numerical, yes/no toggle, and image upload.

export const FORM_OUTCOMES = ['request', 'assessment', 'job'] as const;
export type FormOutcome = (typeof FORM_OUTCOMES)[number];

// The four choice types carry `options`; the rest never do.
export const FORM_QUESTION_TYPES = [
	'short_text',
	'long_text',
	'dropdown', // single-select dropdown
	'dropdown_multi', // multi-select dropdown
	'radio', // single-select buttons
	'checkbox', // multi-select boxes
	'number',
	'yes_no',
	'image_upload'
] as const;
export type FormQuestionType = (typeof FORM_QUESTION_TYPES)[number];

export const FORM_CHOICE_TYPES: readonly FormQuestionType[] = [
	'dropdown',
	'dropdown_multi',
	'radio',
	'checkbox'
];

export function isChoiceQuestion(type: FormQuestionType): boolean {
	return FORM_CHOICE_TYPES.includes(type);
}

// Caps. Bounded on purpose — a public form stays fast to render and safe to store. The builder shows these
// as limits; the validator refuses past them.
export const FORM_MAX_QUESTIONS = 20; // across all sections combined
export const FORM_MAX_SECTIONS = 8;
export const FORM_MAX_OPTIONS = 20; // per choice question
export const FORM_MAX_PHOTOS = 10;

export const FORM_QUESTION_LABEL_MAX = 200;
export const FORM_QUESTION_HELP_MAX = 500;
export const FORM_OPTION_MAX = 120;
export const FORM_SECTION_TITLE_MAX = 120;
export const FORM_TITLE_MAX = 160;
export const FORM_DESCRIPTION_MAX = 2000;
export const FORM_NAME_MAX = 120;
export const FORM_CONFIRMATION_TITLE_MAX = 160;
export const FORM_CONFIRMATION_MESSAGE_MAX = 2000;
export const FORM_REDIRECT_URL_MAX = 500;

// The content document ------------------------------------------------------------------------------------

// The contact block is always the first section of the live form and cannot be removed. Name is always
// shown; the rest can be hidden. `marketing_consent` adds the opt-in checkbox Jobber shows beside email/phone.
export interface ContactBlock {
	name: { required: boolean };
	email: { shown: boolean; required: boolean; marketing_consent: boolean };
	phone: { shown: boolean; required: boolean; marketing_consent: boolean };
	company: { shown: boolean; required: boolean };
	address: { shown: boolean; required: boolean };
}

export interface FormQuestion {
	id: string; // uuid, stable across edits so submitted answers can be mapped later (4C/4D)
	type: FormQuestionType;
	label: string;
	required: boolean;
	help?: string;
	options?: string[]; // choice types only
}

export interface FormSection {
	id: string; // uuid
	title: string;
	questions: FormQuestion[];
}

export interface FormPhotos {
	enabled: boolean;
	max: number;
}

export interface FormConfirmation {
	title: string;
	message: string;
	redirect_url: string | null;
}

export interface FormContent {
	contact: ContactBlock;
	sections: FormSection[];
	photos: FormPhotos;
	confirmation: FormConfirmation;
}

// API read shapes -----------------------------------------------------------------------------------------

export interface FormListItem {
	id: string;
	outcome: FormOutcome;
	name: string;
	is_enabled: boolean;
	is_default: boolean;
	archived_at: string | null;
	revision: number;
	has_draft: boolean;
	published_version_number: number | null;
	title: string; // published title if published, else the draft title
}

export interface FormVersionView {
	version_id: string;
	version_number: number;
	revision: number;
	title: string;
	description: string | null;
	content: FormContent;
	published_at: string | null;
}

export interface FormDetail {
	id: string;
	outcome: FormOutcome;
	name: string;
	is_enabled: boolean;
	is_default: boolean;
	archived_at: string | null;
	revision: number;
	draft: FormVersionView | null;
	published: FormVersionView | null;
}
