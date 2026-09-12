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

// Booking rules — Part 4B-2a/4B-2c. Only assessment/job forms have a row; a request form is reviewed by
// staff and never books a slot (20260913160000_contractor_settings_booking_rules_foundation.sql).
export const BOOKING_OUTCOMES = ['assessment', 'job'] as const;
export type BookingOutcome = (typeof BOOKING_OUTCOMES)[number];

export function isBookingOutcome(outcome: FormOutcome): outcome is BookingOutcome {
	return (BOOKING_OUTCOMES as readonly FormOutcome[]).includes(outcome);
}

// Same bounds as the `form_booking_rules` table's own check constraints — kept here so the builder and the
// Zod validator enforce exactly what the database will.
export const BOOKING_MIN_NOTICE_MAX_MINUTES = 43200; // 30 days
export const BOOKING_SLOT_INTERVAL_MIN_MINUTES = 5;
export const BOOKING_SLOT_INTERVAL_MAX_MINUTES = 480; // 8 hours
export const BOOKING_VISIT_DURATION_MIN_MINUTES = 5;
export const BOOKING_VISIT_DURATION_MAX_MINUTES = 1440; // 24 hours
export const BOOKING_ARRIVAL_WINDOW_MAX_MINUTES = 480; // 8 hours
export const BOOKING_BUFFER_MAX_MINUTES = 480; // 8 hours
export const BOOKING_MAX_SERVICES = 20;

export interface BookingRules {
	requires_booking_approval: boolean;
	service_area_enabled: boolean;
	min_notice_minutes: number;
	slot_interval_minutes: number;
	visit_duration_minutes: number;
	arrival_window_minutes: number | null;
	buffer_minutes: number;
	revision: number;
}

export interface BookableService {
	catalog_item_id: string;
	name: string;
	unit_price_minor: number;
	archived_at: string | null;
}

// What the Booking tab needs about the business itself, read-only here — Business Profile owns editing it.
export interface BookingOrgReadiness {
	hours_set: boolean;
	service_area_ready: boolean;
}

export interface BookingDetail {
	rules: BookingRules;
	services: BookableService[];
	organization: BookingOrgReadiness;
}

export interface BookingSlot {
	slot_date: string;
	start_time: string;
	end_time: string;
	starts_at: string;
	ends_at: string;
}
