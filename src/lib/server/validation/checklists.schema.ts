import { z } from 'zod';
import {
	CHECKLIST_ITEM_TYPES,
	CHECKLIST_LONG_TEXT_MAX,
	CHECKLIST_MAX_OPTIONS,
	CHECKLIST_MAX_QUESTIONS,
	CHECKLIST_SHORT_TEXT_MAX
} from '$lib/checklists/types';

// Every limit here has a twin in 20260911100000_job_checklists_foundation.sql. The database is the one that
// decides; this exists so a person gets a sentence about the field they typed in instead of a constraint
// name.

const questionSchema = z
	.object({
		label: z.string().trim().min(1, 'A question needs some words.').max(200),
		item_type: z.enum(CHECKLIST_ITEM_TYPES),
		required: z.boolean().default(false),
		options: z.array(z.string().trim().min(1).max(120)).max(CHECKLIST_MAX_OPTIONS).optional()
	})
	.superRefine((question, context) => {
		// Only a dropdown carries choices, and a dropdown without them cannot be answered.
		const choices = question.options ?? [];
		if (question.item_type === 'dropdown' && choices.length === 0) {
			context.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'A "choose one" question needs at least one choice.'
			});
		}
		if (question.item_type !== 'dropdown' && choices.length > 0) {
			context.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'Only a "choose one" question can have choices.'
			});
		}
	});

const questionsSchema = z
	.array(questionSchema)
	.min(1, 'A checklist needs at least one question.')
	.max(CHECKLIST_MAX_QUESTIONS);

export const checklistTemplateCreateSchema = z.object({
	name: z.string().trim().min(1, 'Give this checklist a name.').max(120),
	items: questionsSchema
});

export const checklistTemplateUpdateSchema = checklistTemplateCreateSchema;

export const checklistTemplateArchiveSchema = z.object({
	archived: z.boolean()
});

export const jobChecklistAttachSchema = z.object({
	template_id: z.string().uuid()
});

// An answer is `null` (clear it), a boolean, a number, or a string. The database has the last word on
// whether the value fits its question — only that side knows what type the question is.
const answerValueSchema = z.union([
	z.null(),
	z.boolean(),
	z.number().finite(),
	z.string().max(CHECKLIST_LONG_TEXT_MAX)
]);

export const visitChecklistAnswersSchema = z.object({
	answers: z
		.array(
			z.object({
				item_id: z.string().uuid(),
				value: answerValueSchema
			})
		)
		.min(1)
		.max(CHECKLIST_MAX_QUESTIONS)
});

export { CHECKLIST_SHORT_TEXT_MAX };
