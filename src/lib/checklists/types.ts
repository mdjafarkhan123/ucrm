// The checklist vocabulary, in one place so the browser renders exactly what the database validates.
//
// Jobber's own question list is short answer, long answer, dropdown, checkbox, numerical answer, image
// upload, date picker and signature. Ours is that list minus the last two on purpose: signature is Part
// 15d's whole subject, and image upload would be a second way to do what visit photos already do.

export const CHECKLIST_ITEM_TYPES = [
	'checkbox',
	'short_text',
	'long_text',
	'number',
	'dropdown',
	'date'
] as const;

export type ChecklistItemType = (typeof CHECKLIST_ITEM_TYPES)[number];

/** What a person calls each question type when they are building a checklist. */
export const CHECKLIST_ITEM_TYPE_LABELS: Record<ChecklistItemType, string> = {
	checkbox: 'Tick box',
	short_text: 'Short answer',
	long_text: 'Long answer',
	number: 'Number',
	dropdown: 'Choose one',
	date: 'Date'
};

/** Only a dropdown carries choices; the database refuses any other shape. */
export const CHECKLIST_ITEM_TYPES_WITH_OPTIONS: ChecklistItemType[] = ['dropdown'];

export const CHECKLIST_MAX_QUESTIONS = 100;
export const CHECKLIST_MAX_OPTIONS = 50;
export const CHECKLIST_SHORT_TEXT_MAX = 500;
export const CHECKLIST_LONG_TEXT_MAX = 5000;

/** A saved answer: `true`, `12.5`, `'2026-09-08'`, `'Left side gate'`, or nothing yet. */
export type ChecklistAnswerValue = string | number | boolean | null;

export type ChecklistQuestion = {
	id: string;
	position: number;
	label: string;
	item_type: ChecklistItemType;
	required: boolean;
	options: string[] | null;
};

/** One question on a visit, carrying that visit's own answer. */
export type VisitChecklistQuestion = ChecklistQuestion & {
	value: ChecklistAnswerValue;
	answered_at: string | null;
	answered_by: string | null;
};

export type ChecklistTemplate = {
	id: string;
	name: string;
	archived: boolean;
	updated_at: string;
	items: ChecklistQuestion[];
};

export type JobChecklist = {
	id: string;
	name: string;
	source_template_id: string | null;
	attached_at: string;
	answers_count: number;
	items: ChecklistQuestion[];
};

export type VisitChecklist = {
	id: string;
	name: string;
	items: VisitChecklistQuestion[];
};

/**
 * Whether one answer counts as given — the browser's copy of
 * `private.checklist_answer_is_complete`, so the warning a person sees before saving says the same thing
 * the database says afterwards. An unticked box is not an answer to "did you do it".
 */
export function checklistAnswerIsComplete(
	itemType: ChecklistItemType,
	value: ChecklistAnswerValue
): boolean {
	if (value === null || value === undefined) return false;
	if (itemType === 'checkbox') return value === true;
	if (typeof value === 'string') return value.trim().length > 0;
	return true;
}

/** How many required questions are still blank across a visit's forms. */
export function outstandingRequired(checklists: VisitChecklist[]): number {
	return checklists.reduce(
		(total, checklist) =>
			total +
			checklist.items.filter(
				(item) => item.required && !checklistAnswerIsComplete(item.item_type, item.value)
			).length,
		0
	);
}
