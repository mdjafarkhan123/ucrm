import { z } from 'zod';
import { BOARD_COLUMN_KEYS, OPPORTUNITY_STAGES } from '$lib/pipeline/stages';
import { BOARD_DATE_PRESETS, BOARD_DIRECTIONS, BOARD_SORTS } from '$lib/server/pipeline/board';
import { OUTCOME_SORTS, OUTCOME_TYPES } from '$lib/pipeline/outcomes';

// Nothing here validates a create. Opportunities are only ever made by the Request trigger, and later by
// the Quote one, so the board has no write path of its own to validate.

export const BOARD_PAGE_SIZE_DEFAULT = 25;
export const BOARD_PAGE_SIZE_MAX = 50;

const isoDay = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use a date like 2026-08-19.');

// The board's filters, written once. The columns and the summary have to be answering about the same
// set of cards, so they cannot each decide for themselves what a salesperson or a date range means.
//
// The salesperson is either everybody, nobody, or one person's id, so it is one parameter rather than a
// filter and a flag that can disagree with each other.
const boardFilterShape = {
	owner: z.union([z.literal('all'), z.literal('unassigned'), z.string().uuid()]).default('all'),
	date: z.enum(BOARD_DATE_PRESETS).default('all'),
	from: isoDay.optional(),
	to: isoDay.optional()
};

type DateRangeInput = { date?: string; from?: string; to?: string };

// A custom range needs at least one end, and cannot end before it starts. Applied to both schemas, so a
// range the columns refuse is never one the summary quietly accepts.
function withDateRules<Schema extends z.ZodType<DateRangeInput>>(schema: Schema) {
	return schema
		.refine(
			(query) => query.date !== 'custom' || query.from !== undefined || query.to !== undefined,
			{
				message: 'Pick at least one end of the date range.',
				path: ['from']
			}
		)
		.refine((query) => !query.from || !query.to || query.from <= query.to, {
			message: 'The end of the range cannot be before its start.',
			path: ['to']
		});
}

// One column's page. The board asks for each column separately so a long column can keep loading without
// the others re-fetching, and every control below narrows or reorders that one column.
//
// `stage` carries a column name, which is a real stage for six of the seven and the named logical column
// `assessment` for the collapsed one. A closed list, never a caller-supplied set of stages: the only
// grouping that exists is the one the product approved.
export const boardQuerySchema = withDateRules(
	z.object({
		stage: z.enum(BOARD_COLUMN_KEYS),
		cursor: z.string().min(3).max(200).optional(),
		limit: z.coerce.number().int().min(1).max(BOARD_PAGE_SIZE_MAX).default(BOARD_PAGE_SIZE_DEFAULT),
		sort: z.enum(BOARD_SORTS).default('stage'),
		direction: z.enum(BOARD_DIRECTIONS).default('desc'),
		...boardFilterShape
	})
);

// The whole board's headings, for the same filtered set the columns are paging through. No stage, no
// cursor and no sort: a total does not care what order the cards are in, and asking for one is not a way
// to read money the caller may not see.
export const boardSummaryQuerySchema = withDateRules(z.object({ ...boardFilterShape }));

// Dragging a card. `to_stage` only needs to be a real stage name here -- a garbled value fails as a field
// error instead of a raw database exception. Whether this particular move is allowed from the card's
// current stage is decided by `dragActionFor` in the route and, underneath it, by the database gate;
// neither trusts this schema for that. `starts_at`/`ends_at` matter only for the one action that needs
// them (scheduling an assessment) -- the route ignores them for every other target stage.
export const dragOpportunitySchema = z
	.object({
		to_stage: z.enum(OPPORTUNITY_STAGES),
		starts_at: z.iso.datetime({ offset: true }).nullish(),
		ends_at: z.iso.datetime({ offset: true }).nullish(),
		// Only the conversion drop needs one, and the route insists on it there. A retry of the same drag
		// carries the same key, so a doubled request gets the first quote back instead of a second one.
		idempotency_key: z.string().uuid('Start a new action and try again.').optional()
	})
	.refine((value) => (value.starts_at == null) === (value.ends_at == null), {
		message: 'Set both a start and an end time, or leave them both out.',
		path: ['starts_at']
	})
	.refine(
		(value) =>
			!value.starts_at || !value.ends_at || Date.parse(value.ends_at) > Date.parse(value.starts_at),
		{ message: 'End time must be after the start time.', path: ['ends_at'] }
	);

// The card's ownership action. `null` clears ownership; eligibility for a real id is checked by the
// database trigger, not here, so this only shapes the request.
export const assignOpportunityOwnerSchema = z.object({
	owner_user_id: z.string().uuid().nullable()
});

// The Brief's three remaining editable fields, one schema each, following the same `null` clears it
// shape as ownership. Money mirrors the database's own `>= 0` constraint so a negative amount is a field
// error here rather than a raw check-violation from the RPC; the RPC still enforces it either way for a
// caller who bypasses this route.
export const updateOpportunityValueSchema = z.object({
	estimated_value: z
		.number()
		.finite()
		.min(0, 'Estimated value cannot be negative.')
		.max(9_999_999_999.99, 'That value is too large.')
		.nullable()
});

export const updateOpportunityExpectedCloseSchema = z.object({
	expected_close_on: isoDay.nullable()
});

export const updateOpportunityNextFollowUpSchema = z.object({
	next_follow_up_on: isoDay.nullable()
});

// A Brief Task: a required title, and three optional details. Creating and editing send the same shape,
// because the edit form is the create form with the current values in it, and an edit replaces all four
// fields rather than patching one. The lengths mirror the database's own checks so a too-long title is a
// field error here instead of a raw constraint violation from the write function.
export const taskInputSchema = z.object({
	title: z
		.string()
		.trim()
		.min(2, 'Give the task a title.')
		.max(160, 'That title is too long. Keep it under 160 characters.'),
	instructions: z
		.string()
		.trim()
		.max(2000, 'These instructions are too long.')
		.nullish()
		.transform((value) => value || null),
	// Whether this person may actually be given pipeline work is the database's answer, not this one.
	assignee_user_id: z
		.string()
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	due_on: isoDay.nullish().transform((value) => value ?? null)
});

// Completing and reopening are the same request with the flag turned around.
export const taskCompletionSchema = z.object({
	completed: z.boolean()
});

// A Brief Note only ever targets the card's own Request or Client, never a Property -- the generic Notes
// surface's wider `linkedEntityTypeSchema` would let a caller ask for a target this Opportunity has no id
// for.
export const pipelineNoteEntityTypeSchema = z.enum(['request', 'client']);

// Which of the card's two targets a new Note goes on, and its text. Editing sends only the body -- the
// target is fixed at creation, the same way the generic Notes surface treats it.
export const pipelineNoteCreateSchema = z.object({
	entity_type: pipelineNoteEntityTypeSchema,
	body: z.string().trim().min(1, 'Write a note before saving.').max(4000)
});

export const pipelineNoteUpdateSchema = z.object({
	body: z.string().trim().min(1, 'Write a note before saving.').max(4000)
});

// The fixed lost-reason vocabulary, mirroring the database's own check constraint. Leaving it unselected
// is valid; only "Other" requires a note, enforced below the same way the RPC enforces it again itself.
export const LOST_REASON_VALUES = [
	'price_too_high',
	'chose_another_contractor',
	'no_response',
	'project_postponed',
	'work_not_a_fit',
	'duplicate_or_test_request',
	'other'
] as const;

const idempotencyKeySchema = z.string().uuid('Start a new action and try again.');

export const markOpportunityLostSchema = z
	.object({
		idempotency_key: idempotencyKeySchema,
		reason: z
			.enum(LOST_REASON_VALUES)
			.nullish()
			.transform((value) => value ?? null),
		note: z
			.string()
			.trim()
			.max(1000, 'That note is too long.')
			.nullish()
			.transform((value) => value || null)
	})
	.refine((value) => value.reason !== 'other' || Boolean(value.note), {
		message: 'Add a short note for "Other".',
		path: ['note']
	});

export const reopenOpportunitySchema = z.object({
	idempotency_key: idempotencyKeySchema,
	reopen_explanation: z
		.string()
		.trim()
		.min(1, 'A short explanation is required to reopen.')
		.max(500, 'Keep the explanation under 500 characters.')
});

// The Sales Outcomes report's own query. Type is required rather than defaulted here -- the route decides
// the default, because the browser's own default (Won) and a bare API call are not obliged to agree.
export const outcomePageQuerySchema = withDateRules(
	z.object({
		type: z.enum(OUTCOME_TYPES),
		cursor: z.string().min(3).max(200).optional(),
		limit: z.coerce.number().int().min(1).max(BOARD_PAGE_SIZE_MAX).default(BOARD_PAGE_SIZE_DEFAULT),
		sort: z.enum(OUTCOME_SORTS).default('outcome_at'),
		direction: z.enum(BOARD_DIRECTIONS).default('desc'),
		date: z.enum(BOARD_DATE_PRESETS).default('all'),
		from: isoDay.optional(),
		to: isoDay.optional()
	})
);
