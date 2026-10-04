import { z } from 'zod';
import {
	setupValueError,
	storedSetupValue,
	type SetupAnswers,
	type SetupFact
} from '$lib/setup/catalogue';

// One autosave: one or more facts from the setup wizard. The published setup version decides what a fact
// may hold, so the same rule that the page shows beside the field is the one that refuses the save here.
const answerSchema = z.object({
	fact_key: z.string().max(80),
	// null clears the answer.
	availability: z.enum(['have', 'not_yet', 'need_help']).nullable(),
	value: z
		.string()
		.nullish()
		.transform((value) => value?.trim() || null),
	note: z
		.string()
		.max(500, 'Keep the note under 500 characters.')
		.nullish()
		.transform((value) => value?.trim() || null)
});

/**
 * `saved` is what the organization has already saved. A pick (A5f) is checked against its list as this same
 * save leaves it, so a list and a pick of it can arrive together.
 */
export const setupAnswersSchema = (facts: Map<string, SetupFact>, saved: SetupAnswers = {}) =>
	z
		.object({ answers: z.array(answerSchema).min(1).max(50) })
		.superRefine((input, context) => {
			const after: SetupAnswers = { ...saved };
			for (const answer of input.answers)
				after[answer.fact_key] = answer.availability
					? { availability: answer.availability, value: answer.value, note: null }
					: undefined;
			const seen = new Set<string>();
			for (const answer of input.answers) {
				// Errors are keyed by the fact, so the page can put each one under its own field.
				const issue = (message: string) =>
					context.addIssue({ code: 'custom', path: [answer.fact_key], message });

				const fact = facts.get(answer.fact_key);
				if (!fact) {
					issue('This question is not part of setup.');
					continue;
				}
				if (seen.has(answer.fact_key)) issue('This answer was sent twice.');
				seen.add(answer.fact_key);

				if (answer.availability === null) continue;
				if (answer.availability !== 'have') {
					if (!fact.canDefer) issue('This one needs an answer.');
					continue;
				}
				if (!answer.value) {
					issue('Enter an answer.');
					continue;
				}
				const error = setupValueError(fact, answer.value, after);
				if (error) issue(error);
			}
		})
		.transform((input) => ({
			answers: input.answers.map((answer) => {
				const fact = facts.get(answer.fact_key);
				return {
					fact_key: answer.fact_key,
					availability: answer.availability,
					value:
						fact && answer.availability === 'have' && answer.value
							? storedSetupValue(fact, answer.value)
							: null,
					note: answer.availability && answer.availability !== 'have' ? answer.note : null
				};
			})
		}));

export type SetupAnswersInput = z.infer<ReturnType<typeof setupAnswersSchema>>;

export const setupSectionDoneSchema = z.object({ done: z.boolean() });

export const setupReminderEmailsSchema = z.object({ emails_on: z.boolean() }).strict();

// Client onboarding A5c: one file a client is about to add to a photo or file answer. Shape only — whether the
// question takes this kind of file is the route's check, against the published question.
export const setupFileUploadSchema = z
	.object({
		fact_key: z.string().max(80),
		// A5e: the file box of a list question; left out for a photo or file question.
		field_key: z
			.string()
			.regex(/^[a-z][a-z0-9_]{0,39}$/)
			.optional(),
		file_name: z.string().trim().min(1).max(255),
		// Browsers report some files with no type at all; the route stores the type the name says.
		mime_type: z.string().trim().max(127),
		size_bytes: z.number().int().positive()
	})
	.strict();

const FILE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The files a photo or file answer holds, for the page to show: up to 20, the most one answer holds.
export const setupFileIdsSchema = z
	.string()
	.transform((value) => value.split(',').filter(Boolean))
	.pipe(z.array(z.string().regex(FILE_ID)).min(1).max(20));
