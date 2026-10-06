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
import { LAUNCH_NOT_YET_NOTE_MAX, LAUNCH_RECORD_REASON_MAX } from '$lib/setup/launch-approval';
import { LAUNCH_CHECK_KEYS, LAUNCH_CHECK_REASON_MAX } from '$lib/setup/launch-checks';
import {
	HANDOVER_GUIDES_MAX,
	HANDOVER_GUIDE_TITLE_MAX,
	HANDOVER_SUMMARY_MAX,
	LINK_MAX,
	TRAINING_ATTENDEES_MAX,
	TRAINING_NAME_MAX,
	TRAINING_ROLE_MAX,
	TRAINING_TASKS_MAX,
	TRAINING_TEXT_MAX
} from '$lib/setup/training';
import {
	PROVIDER_WAITS,
	PROVIDER_WAIT_NOTE_MAX,
	PROVIDER_WAIT_STATUSES
} from '$lib/setup/provider-waits';
import {
	PREVIEW_CARDS_MAX,
	PREVIEW_CHOICES,
	PREVIEW_KINDS,
	PREVIEW_LINK_MAX,
	PREVIEW_NOTE_MAX,
	PREVIEW_SCREENSHOTS_MAX,
	PREVIEW_SCREENSHOT_TYPES,
	PREVIEW_SUMMARY_MAX,
	PREVIEW_TITLE_MAX
} from '$lib/setup/preview';

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

// Client onboarding E2: Jafar moves one outside wait to a stage, or clears it back to not started (`status`
// null). "You need to do something" needs a note saying what to do.
export const setupProviderWaitSchema = z
	.object({
		wait_key: z.enum(PROVIDER_WAITS, 'Choose a wait.'),
		status: z.enum(PROVIDER_WAIT_STATUSES, 'Choose a stage.').nullable(),
		note: z
			.string()
			.trim()
			.max(PROVIDER_WAIT_NOTE_MAX, `Keep the note under ${PROVIDER_WAIT_NOTE_MAX} characters.`)
			.nullish()
			.transform((value) => value || null)
	})
	.strict()
	.refine((input) => input.status !== 'action_needed' || input.note !== null, {
		path: ['note'],
		message: 'Say what the client needs to do.'
	});
export type SetupProviderWaitInput = z.infer<typeof setupProviderWaitSchema>;

// Client onboarding E3: the preview (plan §6). A screenshot is already uploaded; its size is never taken from the
// browser — the route measures it in storage.
const previewScreenshotSchema = z
	.object({
		object_key: z.string().min(1).max(600),
		file_name: z.string().trim().min(1).max(255),
		mime_type: z.enum(PREVIEW_SCREENSHOT_TYPES, 'A screenshot must be a photo.'),
		has_thumbnail: z.boolean().default(false),
		// Sent back with a screenshot already stored; ignored, as the route measures it again.
		byte_size: z.number().optional()
	})
	.strict();
const previewScreenshotsSchema = z
	.array(previewScreenshotSchema)
	.max(PREVIEW_SCREENSHOTS_MAX, `Add up to ${PREVIEW_SCREENSHOTS_MAX} screenshots.`)
	.default([]);

const previewCardSchema = z
	.object({
		id: z.string().min(1).max(64),
		title: z
			.string()
			.trim()
			.min(1, 'Give the card a title.')
			.max(PREVIEW_TITLE_MAX, `Keep the title under ${PREVIEW_TITLE_MAX} characters.`),
		summary: z
			.string()
			.trim()
			.min(1, 'Write what the client should check.')
			.max(PREVIEW_SUMMARY_MAX, `Keep the summary under ${PREVIEW_SUMMARY_MAX} characters.`),
		link: z
			.string()
			.trim()
			.max(PREVIEW_LINK_MAX, `Keep the link under ${PREVIEW_LINK_MAX} characters.`)
			.nullish()
			.transform((value) => value || null)
			.refine((value) => value === null || /^https:\/\/\S+$/.test(value), {
				message: 'Use a full address starting with https://.'
			}),
		screenshots: previewScreenshotsSchema
	})
	.strict();

// Jafar saves his draft whole: the cards in order.
export const setupPreviewDraftSchema = z
	.object({
		cards: z
			.array(previewCardSchema)
			.min(1, 'Add at least one card.')
			.max(PREVIEW_CARDS_MAX, `Keep it to ${PREVIEW_CARDS_MAX} cards.`)
			.refine((cards) => new Set(cards.map((card) => card.id)).size === cards.length, {
				message: 'Each card needs its own id.'
			})
	})
	.strict();
export type SetupPreviewDraftInput = z.infer<typeof setupPreviewDraftSchema>;

export const setupPreviewVersionSchema = z
	.object({ version: z.number().int().min(1, 'Choose a preview.') })
	.strict();

export const setupPreviewSortSchema = z
	.object({
		version: z.number().int().min(1),
		card_id: z.string().min(1).max(64),
		kind: z.enum(PREVIEW_KINDS, 'Choose a label.')
	})
	.strict();

// The client's choice on one card; `choice` null clears it. Every choice but Looks right needs a note.
export const setupPreviewNoteSchema = z
	.object({
		version: z.number().int().min(1),
		card_id: z.string().min(1).max(64),
		choice: z.enum(PREVIEW_CHOICES, 'Choose an option.').nullable(),
		note: z
			.string()
			.trim()
			.max(PREVIEW_NOTE_MAX, `Keep the note under ${PREVIEW_NOTE_MAX} characters.`)
			.nullish()
			.transform((value) => value || null),
		screenshots: previewScreenshotsSchema
	})
	.strict()
	.refine(
		(input) => input.choice === null || input.choice === 'looks_right' || input.note !== null,
		{
			path: ['note'],
			message: 'Say what should change.'
		}
	);
export type SetupPreviewNoteInput = z.infer<typeof setupPreviewNoteSchema>;

export const setupPreviewScreenshotPresignSchema = z
	.object({
		file_name: z.string().trim().min(1).max(255),
		mime_type: z.enum(
			PREVIEW_SCREENSHOT_TYPES,
			'A screenshot must be a photo (JPG, PNG, WebP or GIF).'
		),
		size_bytes: z
			.number()
			.int()
			.positive('That file is empty.')
			.max(10 * 1024 * 1024, 'Each screenshot must be 10 MB or smaller.')
	})
	.strict();

// E4: the approver's answer to a launch approval request, signed in or through the link.
const launchNoteField = z
	.string()
	.trim()
	.max(LAUNCH_NOT_YET_NOTE_MAX, `Keep the note under ${LAUNCH_NOT_YET_NOTE_MAX} characters.`)
	.nullish()
	.transform((value) => value || null);

export const setupLaunchDecisionSchema = z
	.object({
		version: z.number().int().min(1, 'Choose a preview.'),
		decision: z.enum(['approve', 'not_yet'], 'Choose Approve or Not yet.'),
		// The box the approver ticks; the server records the wording, not this flag.
		agreed: z.boolean().optional(),
		note: launchNoteField
	})
	.strict()
	.refine((input) => input.decision !== 'approve' || input.agreed === true, {
		message: 'Tick the box to approve.',
		path: ['agreed']
	});

export const setupLaunchLinkDecisionSchema = z
	.object({
		decision: z.enum(['approve', 'not_yet'], 'Choose Approve or Not yet.'),
		agreed: z.boolean().optional(),
		note: launchNoteField
	})
	.strict()
	.refine((input) => input.decision !== 'approve' || input.agreed === true, {
		message: 'Tick the box to approve.',
		path: ['agreed']
	});

// E4: Jafar records an approval given by phone or email, saying how it was given.
export const setupLaunchRecordSchema = z
	.object({
		version: z.number().int().min(1, 'Choose a preview.'),
		reason: z
			.string()
			.trim()
			.min(1, 'Say how the approval was given.')
			.max(LAUNCH_RECORD_REASON_MAX, `Keep it under ${LAUNCH_RECORD_REASON_MAX} characters.`)
	})
	.strict();

// Client onboarding E5: Jafar ticks one launch check ('checked'), marks it Doesn't apply with a reason, or clears it
// (`outcome` null), on the version he is checking.
export const setupLaunchCheckSchema = z
	.object({
		version: z.number().int().min(1, 'Choose a preview.'),
		check_key: z.enum(LAUNCH_CHECK_KEYS, 'Choose a check.'),
		outcome: z.enum(['checked', 'not_applicable'], 'Choose tick or doesn’t apply.').nullable(),
		reason: z
			.string()
			.trim()
			.max(LAUNCH_CHECK_REASON_MAX, `Keep the reason under ${LAUNCH_CHECK_REASON_MAX} characters.`)
			.nullish()
			.transform((value) => value || null)
	})
	.strict()
	.refine((input) => input.outcome !== 'not_applicable' || input.reason !== null, {
		path: ['reason'],
		message: 'Say why this check doesn’t apply.'
	});
export type SetupLaunchCheckInput = z.infer<typeof setupLaunchCheckSchema>;

// Client onboarding E6: training and handover (plan §6).
const optionalText = (max: number) =>
	z
		.string()
		.trim()
		.max(max, `Keep it under ${max} characters.`)
		.nullish()
		.transform((value) => value || null);

const httpsLink = (missing: string) =>
	z
		.string()
		.trim()
		.min(1, missing)
		.max(LINK_MAX, `Keep the link under ${LINK_MAX} characters.`)
		.regex(/^https:\/\/\S+$/, 'Use a full address starting with https://.');

const isTimeZone = (value: string) => {
	try {
		new Intl.DateTimeFormat('en-GB', { timeZone: value });
		return true;
	} catch {
		return false;
	}
};

export const setupTrainingSchema = z
	.object({
		attendees: z
			.array(
				z
					.object({
						name: z
							.string()
							.trim()
							.min(1, 'Give each person’s name.')
							.max(TRAINING_NAME_MAX, `Keep names under ${TRAINING_NAME_MAX} characters.`),
						role: z
							.string()
							.trim()
							.max(TRAINING_ROLE_MAX, `Keep roles under ${TRAINING_ROLE_MAX} characters.`)
							.default(''),
						email: z.email('Give each person’s email address.').max(320)
					})
					.strict()
			)
			.min(1, 'Add at least one person.')
			.max(TRAINING_ATTENDEES_MAX, `Add up to ${TRAINING_ATTENDEES_MAX} people.`),
		time_zone: z.string().trim().min(1, 'Choose your time zone.').max(64).refine(isTimeZone, {
			message: 'Choose your time zone.'
		}),
		preferred_times: z
			.string()
			.trim()
			.min(1, 'Say which days and times suit you.')
			.max(TRAINING_TEXT_MAX, `Keep it under ${TRAINING_TEXT_MAX} characters.`),
		needs: optionalText(TRAINING_TEXT_MAX),
		top_tasks: optionalText(TRAINING_TASKS_MAX),
		recording_consent: z.boolean('Say whether Uplift may record the training.')
	})
	.strict();
export type SetupTrainingInput = z.infer<typeof setupTrainingSchema>;

export const setupTrainingConsentSchema = z
	.object({ recording_consent: z.boolean('Choose yes or no.') })
	.strict();

// Jafar books or moves training: an exact moment (the browser sends it with its offset) and the meeting link.
export const setupTrainingBookingSchema = z
	.object({
		meeting_at: z.iso.datetime({ offset: true, error: 'Choose the training time.' }),
		meeting_url: httpsLink('Add the Meet or Zoom link.')
	})
	.strict();

export const setupTrainingRecordingSchema = z
	.object({ recording_url: httpsLink('Add the recording link.').nullable() })
	.strict();

export const setupHandoverSchema = z
	.object({
		access_summary: optionalText(HANDOVER_SUMMARY_MAX),
		guides: z
			.array(
				z
					.object({
						title: z
							.string()
							.trim()
							.min(1, 'Give each guide a title.')
							.max(
								HANDOVER_GUIDE_TITLE_MAX,
								`Keep titles under ${HANDOVER_GUIDE_TITLE_MAX} characters.`
							),
						url: httpsLink('Give each guide its link.')
					})
					.strict()
			)
			.max(HANDOVER_GUIDES_MAX, `Add up to ${HANDOVER_GUIDES_MAX} guides.`)
	})
	.strict();
export type SetupHandoverInput = z.infer<typeof setupHandoverSchema>;
