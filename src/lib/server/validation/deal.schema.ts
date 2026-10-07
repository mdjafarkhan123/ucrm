import { z } from 'zod';
import {
	DEAL_NOTE_MAX,
	DEAL_START_STAGES,
	LOST_REASONS,
	OPEN_DEAL_STAGES,
	SHARED_PACKAGES_MAX
} from '$lib/jafar/deals';
import { calendarDate } from './owner.schema';

// Jafar business management B4: what each Deal route accepts. The database checks the same rules again.

const nextStepText = z.string().trim().min(1, 'Say what the next step is.').max(200);
const nextStep = z.object({ text: nextStepText, due_on: calendarDate });

export const dealBoardQuerySchema = z.object({
	stage: z.enum([...OPEN_DEAL_STAGES, 'lost', 'won']),
	/** Opaque cursor from the previous page's `next_cursor`. */
	cursor: z.string().max(300).optional()
});

export const dealStartSchema = z.object({
	relationship_id: z.uuid(),
	stage: z.enum(DEAL_START_STAGES),
	next_action: nextStep
});

/** Move to another open stage. Pricing shared has its own route; Lost has its own. */
export const dealMoveSchema = z.object({
	stage: z.enum(OPEN_DEAL_STAGES).exclude(['pricing_shared']),
	/** Absent keeps the current next step. */
	next_action: nextStep.optional()
});

export const dealShareSchema = z.object({
	package_slugs: z
		.array(
			z
				.string()
				.trim()
				.toLowerCase()
				.regex(/^[a-z0-9]+(-[a-z0-9]+)*$/)
		)
		.min(1, 'Choose the package you shared.')
		.max(SHARED_PACKAGES_MAX)
		.refine((slugs) => new Set(slugs).size === slugs.length, 'Choose each package once.'),
	billing: z.enum(['month', 'year']).default('month'),
	follow_up: nextStep
});

export const dealLostSchema = z.object({
	reason: z.enum(LOST_REASONS, 'Choose why the Deal was lost.'),
	note: z
		.string()
		.trim()
		.max(DEAL_NOTE_MAX)
		.nullish()
		.transform((value) => value || null)
});

export const dealReopenSchema = z.object({ next_action: nextStep });

export const dealTermsSchema = z.object({
	terms: z
		.string()
		.trim()
		.max(DEAL_NOTE_MAX)
		.nullable()
		.transform((value) => value || null)
});

/** B5: who looks after the new client's setup; null is Jafar. */
export const setupOwnerSchema = z.object({ member_id: z.uuid().nullable() });
