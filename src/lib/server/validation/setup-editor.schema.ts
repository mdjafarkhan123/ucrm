import { z } from 'zod';
import { SETUP_QUESTION_KINDS } from '$lib/setup/catalogue';

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

const questionSchema = z
	.object({
		type: z.literal('question'),
		// Null for a question added in this draft; the database makes its key from the stage and wording.
		fact_key: z
			.string()
			.regex(/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/)
			.max(80)
			.nullable(),
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
		options: z
			.array(
				z.object({
					// Null for a choice added in this draft.
					value: z.string().regex(OPTION_VALUE).nullable(),
					label: z
						.string()
						.trim()
						.min(1, 'Write the choice, or remove it.')
						.max(100, 'Keep each choice under 100 characters.')
				})
			)
			.max(50, 'A question can offer up to 50 choices.')
			.nullable()
	})
	.superRefine((question, context) => {
		if (question.fact_key === null && question.kind === null)
			context.addIssue({ code: 'custom', path: ['kind'], message: 'Choose an answer type.' });
		if (question.kind !== 'choice') return;
		const labels = (question.options ?? []).map((option) => option.label.toLowerCase());
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
		options: question.kind === 'choice' ? choiceValues(question.options ?? []) : null
	}));

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
