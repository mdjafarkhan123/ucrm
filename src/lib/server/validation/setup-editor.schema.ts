import { z } from 'zod';
import { BUILT_IN_FACTS, SETUP_QUESTION_KINDS } from '$lib/setup/catalogue';
import { SETUP_FILE_KINDS, SETUP_MAX_FILES_CHOICES } from '$lib/setup/files';
import {
	SETUP_LIST_FIELD_KINDS,
	SETUP_LIST_MAX_FIELDS,
	SETUP_MAX_ROWS_CHOICES
} from '$lib/setup/lists';

// Client onboarding A4: Jafar's setup stage editor (plan §2.1, ADR 0006). The limits mirror the database
// checks on setup_stages, so a bad value is explained here rather than refused there.

const draftRevision = {
	version_id: z.string().uuid('The draft identifier is invalid.'),
	revision: z.number().int().positive()
};

const stageSchema = z.object({
	// Null for a stage added in this draft; the database makes its key from the title.
	key: z
		.string()
		.regex(/^[a-z][a-z0-9_]*$/)
		.max(40)
		.nullable(),
	title: z
		.string()
		.trim()
		.min(2, 'Give the stage a name of at least 2 characters.')
		.max(80, 'Keep the name under 80 characters.'),
	description: z.string().trim().max(300, 'Keep the description under 300 characters.'),
	// Null shows the stage to every client.
	service_key: z
		.string()
		.regex(/^[a-z][a-z0-9_]{1,59}$/, 'Pick a service from your list.')
		.nullable()
});

export const saveSetupDraftSchema = z.object({
	...draftRevision,
	stages: z
		.array(stageSchema)
		.min(1, 'Setup needs at least one stage.')
		.max(30, 'Setup can have up to 30 stages.')
		.refine(
			(stages) => new Set(stages.map((stage) => stage.title.toLowerCase())).size === stages.length,
			'Two stages have the same name. Give each stage its own name.'
		)
});

export const setupDraftRevisionSchema = z.object(draftRevision);

// Client onboarding A5: one stage's headings and questions, in order. The limits mirror setup_items.

const hint = z
	.string()
	.trim()
	.max(300, 'Keep the help line under 300 characters.')
	.nullish()
	.transform((value) => value || null);

const headingSchema = z.object({
	type: z.literal('heading'),
	label: z
		.string()
		.trim()
		.min(1, 'Give the heading a title.')
		.max(200, 'Keep the heading under 200 characters.'),
	hint
});

const OPTION_VALUE = /^[a-z0-9_]{1,60}$/;
const FACT_KEY = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;
const SERVICE_KEY = /^[a-z][a-z0-9_]{1,59}$/;

// Client onboarding A5b: one "show only if" condition. An earlier answer is named by its key, or by `item`, the
// 1-based position of a question above it in this save that has no key yet; or the package includes a service.
// The shape mirrors private.setup_show_if_shape_ok, which checks it again.
const conditionSchema = z
	.object({
		fact_key: z.string().optional(),
		item: z.number().int().positive().optional(),
		values: z
			.array(z.string().min(1).max(120))
			.max(60, 'A rule can match up to 60 answers.')
			.optional(),
		service_key: z.string().optional()
	})
	.strict()
	.superRefine((condition, context) => {
		if (condition.service_key !== undefined) {
			if (condition.fact_key !== undefined || condition.item !== undefined || condition.values)
				context.addIssue({ code: 'custom', message: 'This rule is not valid.' });
			else if (!SERVICE_KEY.test(condition.service_key))
				context.addIssue({ code: 'custom', message: 'Choose a service for each rule.' });
			return;
		}
		if ((condition.fact_key === undefined) === (condition.item === undefined))
			context.addIssue({ code: 'custom', message: 'This rule is not valid.' });
		else if (
			condition.fact_key !== undefined &&
			(!FACT_KEY.test(condition.fact_key) || condition.fact_key.length > 80)
		)
			context.addIssue({ code: 'custom', message: 'Choose a question for each rule.' });
		else if (!condition.values?.length)
			context.addIssue({ code: 'custom', message: 'Tick at least one answer for each rule.' });
	});

/**
 * A rule on a built-in question: its answer type and choices live in code (ADR 0006), so the database cannot
 * check them and this does. Null when the rule is fine.
 */
function builtInRuleProblem(factKey: string, values: string[]): string | null {
	const rules = BUILT_IN_FACTS[factKey];
	if (!rules) return null;
	if (rules.kind === 'country')
		return values.every((value) => /^[A-Z]{2}$/.test(value))
			? null
			: 'Choose countries from the list.';
	if (rules.kind !== 'choice' && rules.kind !== 'choice_other')
		return 'Only a question with choices, or country, can decide whether this is shown.';
	const allowed = new Set(rules.options?.map((option) => option.value));
	return values.every((value) => allowed.has(value)) ? null : 'Choose answers from the list.';
}

const choiceSchema = z.object({
	// Null for a choice added in this draft.
	value: z.string().regex(OPTION_VALUE).nullable(),
	label: z
		.string()
		.trim()
		.min(1, 'Write the choice, or remove it.')
		.max(100, 'Keep each choice under 100 characters.')
});

// Client onboarding A5e: one box of an add-another list. The shape mirrors private.setup_list_fields_ok.
const listFieldSchema = z.object({
	// Null for a box added in this draft; its key is made from its name below.
	key: z
		.string()
		.regex(/^[a-z][a-z0-9_]{0,39}$/)
		.nullable(),
	label: z
		.string()
		.trim()
		.min(1, 'Name each box, or remove it.')
		.max(80, 'Keep each box name under 80 characters.'),
	kind: z.enum(SETUP_LIST_FIELD_KINDS),
	required: z.boolean(),
	options: z.array(choiceSchema).max(50, 'A box can offer up to 50 choices.').optional(),
	file_kinds: z.array(z.enum(SETUP_FILE_KINDS)).max(3).optional()
});

const questionSchema = z
	.object({
		type: z.literal('question'),
		// Null for a question added in this draft; the database makes its key from the stage and wording.
		fact_key: z.string().regex(FACT_KEY).max(80).nullable(),
		label: z
			.string()
			.trim()
			.min(1, 'Write the question.')
			.max(200, 'Keep the question under 200 characters.'),
		hint,
		required: z.boolean(),
		can_defer: z.boolean(),
		// Null for a built-in question, whose answer type lives in code.
		kind: z.enum(SETUP_QUESTION_KINDS).nullable(),
		options: z.array(choiceSchema).max(50, 'A question can offer up to 50 choices.').nullable(),
		// Client onboarding A5d: pick one and tick several may add "Other"; tick several may cap its ticks.
		allow_other: z.boolean().optional().default(false),
		max_choices: z.number().int().min(1, 'Allow at least one tick.').nullish(),
		// Client onboarding A5c: a photo or file question's accepted kinds and file limit.
		file_kinds: z.array(z.enum(SETUP_FILE_KINDS)).max(3).nullish(),
		max_files: z.number().int().nullish(),
		// Client onboarding A5e: an add-another list's boxes and row limit.
		list_fields: z
			.array(listFieldSchema)
			.max(SETUP_LIST_MAX_FIELDS, `A list can have up to ${SETUP_LIST_MAX_FIELDS} boxes.`)
			.nullish(),
		max_rows: z.number().int().nullish(),
		// Null, or left out, asks the question always.
		show_if: z
			.array(conditionSchema)
			.max(5, 'A question can have up to 5 rules.')
			.nullish()
			.transform((value) => (value?.length ? value : null))
	})
	.superRefine((question, context) => {
		question.show_if?.forEach((condition, index) => {
			const problem =
				condition.fact_key && condition.values
					? builtInRuleProblem(condition.fact_key, condition.values)
					: null;
			if (problem) context.addIssue({ code: 'custom', path: ['show_if', index], message: problem });
		});
		if (question.fact_key === null && question.kind === null)
			context.addIssue({ code: 'custom', path: ['kind'], message: 'Choose an answer type.' });
		if (question.kind === 'file') {
			if (!question.file_kinds?.length)
				context.addIssue({
					code: 'custom',
					path: ['file_kinds'],
					message: 'Tick at least one kind of file.'
				});
			if (
				!(SETUP_MAX_FILES_CHOICES as readonly number[]).includes(question.max_files ?? Number.NaN)
			)
				context.addIssue({
					code: 'custom',
					path: ['max_files'],
					message: 'Choose how many files a client can add.'
				});
		}
		if (question.kind === 'list') listProblems(question, context);
		if (!isChoiceKind(question.kind)) return;
		const labels = (question.options ?? []).map((option) => option.label.toLowerCase());
		if (question.allow_other && labels.includes('other'))
			context.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'Remove the "Other" choice. "Add Other" already gives clients one.'
			});
		const most = labels.length + (question.allow_other ? 1 : 0);
		if (question.kind === 'multi_choice' && question.max_choices && question.max_choices > most)
			context.addIssue({
				code: 'custom',
				path: ['max_choices'],
				message: `There are only ${most} choices to tick.`
			});
		if (labels.length < 2)
			context.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'Give at least two choices.'
			});
		else if (new Set(labels).size !== labels.length)
			context.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'Two choices have the same words.'
			});
	})
	.transform((question) => ({
		...question,
		options: isChoiceKind(question.kind) ? choiceValues(question.options ?? []) : null,
		allow_other: isChoiceKind(question.kind) && question.allow_other,
		max_choices: question.kind === 'multi_choice' ? (question.max_choices ?? null) : null,
		file_kinds:
			question.kind === 'file'
				? SETUP_FILE_KINDS.filter((kind) => question.file_kinds?.includes(kind))
				: null,
		max_files: question.kind === 'file' ? (question.max_files ?? null) : null,
		list_fields: question.kind === 'list' ? listFieldsPayload(question.list_fields ?? []) : null,
		max_rows: question.kind === 'list' ? (question.max_rows ?? null) : null
	}));

type ListFieldInput = z.infer<typeof listFieldSchema>;

function listProblems(
	question: { list_fields?: ListFieldInput[] | null; max_rows?: number | null },
	context: z.RefinementCtx
) {
	const fields = question.list_fields ?? [];
	if (fields.length === 0)
		context.addIssue({ code: 'custom', path: ['list_fields'], message: 'Add at least one box.' });
	if (!(SETUP_MAX_ROWS_CHOICES as readonly number[]).includes(question.max_rows ?? Number.NaN))
		context.addIssue({
			code: 'custom',
			path: ['max_rows'],
			message: 'Choose how many entries a client can add.'
		});
	const names = fields.map((field) => field.label.toLowerCase());
	if (new Set(names).size !== names.length)
		context.addIssue({
			code: 'custom',
			path: ['list_fields'],
			message: 'Two boxes have the same name.'
		});
	fields.forEach((field, index) => {
		const issue = (message: string) =>
			context.addIssue({ code: 'custom', path: ['list_fields', index], message });
		if (field.kind === 'choice') {
			const labels = (field.options ?? []).map((option) => option.label.toLowerCase());
			if (labels.length < 2) issue(`Give "${field.label}" at least two choices.`);
			else if (new Set(labels).size !== labels.length)
				issue(`Two choices in "${field.label}" have the same words.`);
		}
		if (field.kind === 'file' && !field.file_kinds?.length)
			issue(`Tick at least one kind of file for "${field.label}".`);
	});
}

/**
 * Each box's stored key and only the settings its type uses. A box keeps the key it was saved with, so the
 * rows clients already gave still fill it after it is renamed; a new one takes its key from its name.
 */
function listFieldsPayload(fields: ListFieldInput[]) {
	const used = new Set(fields.flatMap((field) => (field.key ? [field.key] : [])));
	return fields.map((field) => {
		let key = field.key;
		if (!key) {
			const words = field.label
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, '_')
				.replace(/^_+|_+$/g, '')
				.slice(0, 34);
			const base = /^[a-z]/.test(words) ? words : `box_${words}`.replace(/_+$/, '');
			key = base;
			for (let suffix = 2; used.has(key); suffix += 1) key = `${base}_${suffix}`;
			used.add(key);
		}
		return {
			key,
			label: field.label,
			kind: field.kind,
			required: field.required,
			...(field.kind === 'choice' ? { options: choiceValues(field.options ?? []) } : {}),
			...(field.kind === 'file'
				? { file_kinds: SETUP_FILE_KINDS.filter((kind) => field.file_kinds?.includes(kind)) }
				: {})
		};
	});
}

function isChoiceKind(kind: string | null) {
	return kind === 'choice' || kind === 'multi_choice';
}

/**
 * Each choice's stored value. A choice keeps the value it was saved with, so answers already given still match
 * it after it is reworded; a new one takes its value from its words.
 */
function choiceValues(options: { value: string | null; label: string }[]) {
	const used = new Set(options.flatMap((option) => (option.value ? [option.value] : [])));
	return options.map((option) => {
		if (option.value) return { value: option.value, label: option.label };
		const base =
			option.label
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, '_')
				.replace(/^_+|_+$/g, '')
				.slice(0, 50) || 'choice';
		let value = base;
		for (let suffix = 2; used.has(value); suffix += 1) value = `${base}_${suffix}`;
		used.add(value);
		return { value, label: option.label };
	});
}

export const saveSetupStageItemsSchema = z.object({
	...draftRevision,
	items: z
		.array(z.discriminatedUnion('type', [headingSchema, questionSchema]))
		.max(80, 'A stage can hold up to 80 headings and questions.')
});

/** Field errors keyed the way the page names its fields: `stages.2.title`, or `form`. */
export function setupEditorFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [issue.path.join('.') || 'form', issue.message] as const)
	);
}
