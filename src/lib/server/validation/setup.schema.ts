import { z } from 'zod';
import { SETUP_FACTS, setupValueError, storedSetupValue } from '$lib/setup/catalogue';

// One autosave: one or more facts from the setup wizard. The catalogue decides what a fact may hold, so
// the same rule that the page shows beside the field is the one that refuses the save here.
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

export const setupAnswersSchema = z
	.object({ answers: z.array(answerSchema).min(1).max(50) })
	.superRefine((input, context) => {
		const seen = new Set<string>();
		for (const answer of input.answers) {
			// Errors are keyed by the fact, so the page can put each one under its own field.
			const issue = (message: string) =>
				context.addIssue({ code: 'custom', path: [answer.fact_key], message });

			const fact = SETUP_FACTS.get(answer.fact_key);
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
			const error = setupValueError(fact, answer.value);
			if (error) issue(error);
		}
	})
	.transform((input) => ({
		answers: input.answers.map((answer) => {
			const fact = SETUP_FACTS.get(answer.fact_key);
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

export type SetupAnswersInput = z.infer<typeof setupAnswersSchema>;

export const setupSectionDoneSchema = z.object({ done: z.boolean() });

export const setupReminderEmailsSchema = z.object({ emails_on: z.boolean() }).strict();
