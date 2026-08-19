import { z } from 'zod';
import { BOARD_STAGES } from '$lib/pipeline/stages';
import { BOARD_DATE_PRESETS, BOARD_DIRECTIONS, BOARD_SORTS } from '$lib/server/pipeline/board';

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

// One column's page. The board asks for each stage separately so a long column can keep loading without
// the other three re-fetching, and every control below narrows or reorders that one column.
export const boardQuerySchema = withDateRules(
	z.object({
		stage: z.enum(BOARD_STAGES),
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
