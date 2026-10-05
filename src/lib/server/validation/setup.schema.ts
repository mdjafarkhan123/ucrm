import { z } from 'zod';
import {
	setupValueError,
	storedSetupValue,
	type SetupAnswers,
	type SetupFact
} from '$lib/setup/catalogue';
import { SETUP_ANSWER_MAX_BYTES, setupStoredBytes } from '$lib/setup/answer-values';
import { SETUP_REVIEW_NOTE_MAX } from '$lib/setup/review';
import { SETUP_HELP_NOTE_MAX } from '$lib/setup/help';
import { SETUP_READY_REASON_MAX } from '$lib/setup/ready';

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
				else if (setupStoredBytes(storedSetupValue(fact, answer.value)) > SETUP_ANSWER_MAX_BYTES)
					issue('This is too long to save. Shorten some entries or remove a few.');
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

// Client onboarding B13: Send to Uplift. `previous_number` is the newest send the page showed (0 for none), so a
// double press or a send from another device first adds nothing.
export const setupSendSchema = z
	.object({
		confirmed: z.array(z.string().max(40)).max(20),
		previous_number: z.number().int().min(0).max(100_000)
	})
	.strict();

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
// B9a: starting an upload to a protected file question. A protected question is never a list box.
export const protectedDocumentUploadSchema = z
	.object({
		fact_key: z.string().max(80),
		file_name: z.string().trim().min(1).max(255),
		mime_type: z.string().trim().max(127),
		size_bytes: z.number().int().positive()
	})
	.strict();

export const setupFileIdsSchema = z
	.string()
	.transform((value) => value.split(',').filter(Boolean))
	.pipe(z.array(z.string().regex(FILE_ID)).min(1).max(20));

// C3: Uplift's decision on one section of the newest send. A return says what to change and may tick the
// questions to change; an acceptance carries neither.
export const setupSectionReviewSchema = z.discriminatedUnion('decision', [
	z
		.object({
			decision: z.literal('accepted'),
			section_key: z.string().regex(/^[a-z][a-z0-9_]{0,39}$/, 'Choose a section.'),
			send: z.number().int().positive()
		})
		.strict(),
	z
		.object({
			decision: z.literal('returned'),
			section_key: z.string().regex(/^[a-z][a-z0-9_]{0,39}$/, 'Choose a section.'),
			send: z.number().int().positive(),
			note: z
				.string()
				.trim()
				.min(1, 'Say what the client should change.')
				.max(SETUP_REVIEW_NOTE_MAX, `Keep the note under ${SETUP_REVIEW_NOTE_MAX} characters.`),
			question_keys: z.array(z.string().max(80)).max(100).default([])
		})
		.strict()
]);
export type SetupSectionReviewInput = z.infer<typeof setupSectionReviewSchema>;

// Client onboarding C3c: Uplift's answer to a question the client asked help with, on the newest send. A value
// for a question answered in the client's own box, a written note for photos, files and lists; the route checks
// which, and the value itself against the question.
export const setupHelpAnswerSchema = z
	.object({
		send: z.number().int().positive(),
		fact_key: z.string().min(1).max(80),
		value: z
			.string()
			.max(20_000, 'This is too long to save.')
			.nullish()
			.transform((value) => value?.trim() || null),
		note: z
			.string()
			.trim()
			.max(SETUP_HELP_NOTE_MAX, `Keep the note under ${SETUP_HELP_NOTE_MAX} characters.`)
			.nullish()
			.transform((value) => value || null)
	})
	.strict();
export type SetupHelpAnswerInput = z.infer<typeof setupHelpAnswerSchema>;

// Client onboarding C4: Ready for Uplift on the newest send, and taking it back with a reason.
export const setupReadySchema = z.object({ send: z.number().int().positive() }).strict();

export const setupReadyWithdrawSchema = z
	.object({
		reason: z
			.string()
			.trim()
			.min(1, 'Say why you are taking it back.')
			.max(SETUP_READY_REASON_MAX, `Keep it under ${SETUP_READY_REASON_MAX} characters.`)
	})
	.strict();
