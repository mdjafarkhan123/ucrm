import { z } from 'zod';
import {
	PRICING_CATEGORIES,
	QUOTE_TAX_SOURCES,
	JOB_PRICE_BASES,
	JOB_BILLING_TIMINGS
} from '$lib/server/validation/quotes.schema';

// A job's price basis and invoicing timing were first named by the quote-to-job conversion schema. They are
// job facts, so every job route reads them from here rather than reaching into the quote schema for them.
export { JOB_PRICE_BASES, JOB_BILLING_TIMINGS };

// The status and type vocabularies live in `$lib/jobs/statuses.ts` so the browser reads the same list the
// server validates against. Re-exported here because every job route already asks this schema.
export {
	JOB_DERIVED_STATUSES,
	JOB_FILTERABLE_STATUSES,
	JOB_TYPES,
	JOB_OVERVIEW_STATUSES
} from '$lib/jobs/statuses';
export type { JobDerivedStatus, JobType } from '$lib/jobs/statuses';

import { JOB_DERIVED_STATUSES, JOB_TYPES } from '$lib/jobs/statuses';

export const JOB_PAGE_SIZE_DEFAULT = 25;
export const JOB_PAGE_SIZE_MAX = 50;

// Both sorts are index-backed: created walks jobs_organization_created_idx (and jobs_active_idx when the
// archived status is filtered out) and number walks the existing jobs_number_unique. Nothing else is
// offered, so the list can never fall back to sorting a whole tenant's jobs in memory.
export const JOB_SORT_KEYS = ['created', 'number'] as const;

export const jobListQuerySchema = z.object({
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	/** Comma-joined derived statuses, e.g. `unscheduled,ending_soon`. */
	status: z.string().trim().max(200).optional(),
	/** Comma-joined job types, e.g. `one_off`. */
	type: z.string().trim().max(80).optional(),
	sort: z.enum(JOB_SORT_KEYS).default('created'),
	dir: z.enum(['asc', 'desc']).default('desc'),
	created_from: z.string().datetime({ offset: true }).optional(),
	created_to: z.string().datetime({ offset: true }).optional(),
	cursor: z.string().min(3).max(400).optional(),
	limit: z.coerce.number().int().min(1).max(JOB_PAGE_SIZE_MAX).default(JOB_PAGE_SIZE_DEFAULT)
});

export function readJobStatusFilter(raw: string | undefined) {
	return (raw ?? '')
		.split(',')
		.map((value) => value.trim())
		.filter((value): value is (typeof JOB_DERIVED_STATUSES)[number] =>
			(JOB_DERIVED_STATUSES as readonly string[]).includes(value)
		);
}

export function readJobTypeFilter(raw: string | undefined) {
	return (raw ?? '')
		.split(',')
		.map((value) => value.trim())
		.filter((value): value is (typeof JOB_TYPES)[number] =>
			(JOB_TYPES as readonly string[]).includes(value)
		);
}

// --- Direct one-off job creation --------------------------------------------------------------------------

// Money and quantity ceilings mirror the database's own checks on job_line_items, so a bad number is a
// field error on the form rather than a raw constraint violation coming back from the write function.
const MINOR_UNIT_MAX = 1_000_000_000_000;
const QUANTITY_MAX = 1_000_000;

// A job carries up to 100 lines, matching the quote scope it can be built from and the table's trigger.
export const JOB_LINE_MAX = 100;
// A one-off job is created with between one and twenty visits, matching Jobber's create flow and the
// command's own guard.
export const JOB_VISIT_MAX = 20;

const jobMinorAmount = (label: string) =>
	z
		.number()
		.int(`Enter ${label} in whole cents.`)
		.min(0, `${label} cannot be negative.`)
		.max(MINOR_UNIT_MAX, `That ${label} is too large.`);

const jobQuantity = z
	.number()
	.finite()
	.gt(0, 'Enter a quantity above zero.')
	.max(QUANTITY_MAX, 'That quantity is too large.')
	.refine((value) => Math.abs(value * 1000 - Math.round(value * 1000)) < 1e-6, {
		message: 'A quantity can have at most three decimal places.'
	});

// A job's scope rows are always priced product or service work: unlike a quote, a job has no headings,
// notes, or optional add-ons — by the time work is agreed every line is simply part of it.
const jobScopeLineSchema = z
	.object({
		position: z.number().int().min(0),
		category: z.enum(PRICING_CATEGORIES),
		is_labor: z.boolean().default(false),
		source_catalog_item_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null),
		name: z
			.string()
			.trim()
			.min(2, 'Give this line a name.')
			.max(160, 'That name is too long. Keep it under 160 characters.'),
		description: z
			.string()
			.trim()
			.max(2000, 'That description is too long.')
			.nullish()
			.transform((value) => value || null),
		unit_label: z
			.string()
			.trim()
			.max(24, 'Keep the unit under 24 characters.')
			.nullish()
			.transform((value) => value || null),
		quantity: jobQuantity,
		unit_price_minor: jobMinorAmount('a price'),
		unit_cost_minor: jobMinorAmount('a cost'),
		is_taxable: z.boolean().default(true),
		// Carried, not created here: a converted job inherits its quote line's photo, and a rewrite of the
		// scope must not silently drop it. Attaching a new photo to a job line belongs to Part 15.
		image_attachment_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null)
	})
	.refine((value) => !value.is_labor || value.category === 'service', {
		message: 'Labor is always a service.',
		path: ['category']
	});

const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

// The schedule and content of one appointment, shared by every place a visit is described: the create form,
// the add-visits action, and the edit-visit action. The three schedule shapes — scheduled, anytime, and
// unscheduled — are all expressible here.
const visitScheduleFields = {
	visit_date: z
		.string()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Pick a valid date.')
		.nullish()
		.transform((value) => value || null),
	start_time: z
		.string()
		.regex(HHMM, 'Enter a time as HH:MM.')
		.nullish()
		.transform((value) => value || null),
	end_time: z
		.string()
		.regex(HHMM, 'Enter a time as HH:MM.')
		.nullish()
		.transform((value) => value || null),
	all_day: z.boolean().default(false),
	title: z
		.string()
		.trim()
		.max(160, 'That visit title is too long.')
		.nullish()
		.transform((value) => value || null),
	instructions: z
		.string()
		.trim()
		.max(2000, 'Those instructions are too long.')
		.nullish()
		.transform((value) => value || null)
};

// The same rules the database enforces on job_visits, checked first so a bad shape is a field error rather
// than a raw constraint violation coming back from the write.
type VisitShape = {
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
};
const refineVisitShape = (value: VisitShape, context: z.RefinementCtx) => {
	if (value.start_time && !value.visit_date) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: 'Give the visit a date, or tick "Schedule later".',
			path: ['visit_date']
		});
	}
	if (value.end_time && !value.start_time) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: 'Set a start time before an end time.',
			path: ['start_time']
		});
	}
	if (value.start_time && value.end_time && value.end_time <= value.start_time) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: 'The end time has to come after the start time.',
			path: ['end_time']
		});
	}
	if (value.all_day && (value.start_time || value.end_time)) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: 'An anytime visit carries no start or end time.',
			path: ['all_day']
		});
	}
	if (value.all_day && !value.visit_date) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: 'An anytime visit still needs a day.',
			path: ['visit_date']
		});
	}
};

// One appointment as the create form holds it: a position in the job's list and its people, plus the shared
// schedule fields.
const jobVisitSchema = z
	.object({
		position: z.number().int().min(0),
		...visitScheduleFields,
		assignee_ids: z.array(z.string().uuid()).max(50).default([])
	})
	.superRefine(refineVisitShape);

// --- Recurring and as-needed schedules (Part 10) ------------------------------------------------------------

export const RECURRENCE_FREQUENCIES = ['daily', 'weekly', 'monthly', 'yearly'] as const;
export const RECURRENCE_MONTHLY_MODES = ['day_of_month', 'last_day', 'day_of_week'] as const;
export const RECURRENCE_END_MODES = ['after', 'on'] as const;
export const RECURRENCE_DURATION_UNITS = ['day', 'week', 'month', 'year'] as const;

// The same ceiling `private.job_recurrence_limit()` enforces. Weekly for five years is 260 and daily for a
// year is 365, so this clears real service agreements while keeping generation one bounded insert.
export const JOB_RECURRENCE_VISIT_MAX = 400;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const recurrenceDate = (message: string) => z.string().regex(ISO_DATE, message);

// A repeat rule as the form holds it. It is checked here so a schedule that cannot work is a field error on
// the control the person was using, rather than a constraint violation from the write.
export const jobRecurrenceSchema = z
	.object({
		frequency: z.enum(RECURRENCE_FREQUENCIES),
		interval_count: z.number().int().min(1).max(52).default(1),
		/** 0 = Sunday through 6 = Saturday, matching the database's extract(dow). */
		weekdays: z.array(z.number().int().min(0).max(6)).max(7).default([]),
		monthly_mode: z
			.enum(RECURRENCE_MONTHLY_MODES)
			.nullish()
			.transform((value) => value ?? null),
		month_day: z
			.number()
			.int()
			.min(1)
			.max(31)
			.nullish()
			.transform((value) => value ?? null),
		/** 1st through 4th, or 5 meaning the last one in the month. */
		ordinal_week: z
			.number()
			.int()
			.min(1)
			.max(5)
			.nullish()
			.transform((value) => value ?? null),
		ordinal_weekday: z
			.number()
			.int()
			.min(0)
			.max(6)
			.nullish()
			.transform((value) => value ?? null),
		start_date: recurrenceDate('Pick the date this schedule starts.'),
		end_mode: z.enum(RECURRENCE_END_MODES).default('after'),
		duration_count: z
			.number()
			.int()
			.min(1)
			.max(520)
			.nullish()
			.transform((value) => value ?? null),
		duration_unit: z
			.enum(RECURRENCE_DURATION_UNITS)
			.nullish()
			.transform((value) => value ?? null),
		end_date: recurrenceDate('Pick the date this schedule ends.')
			.nullish()
			.transform((value) => value || null),
		start_time: z
			.string()
			.regex(HHMM, 'Enter a time as HH:MM.')
			.nullish()
			.transform((value) => value || null),
		end_time: z
			.string()
			.regex(HHMM, 'Enter a time as HH:MM.')
			.nullish()
			.transform((value) => value || null),
		all_day: z.boolean().default(false)
	})
	.superRefine((value, context) => {
		if (value.frequency === 'weekly' && value.weekdays.length === 0) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Pick at least one day of the week.',
				path: ['weekdays']
			});
		}
		if (value.frequency === 'monthly') {
			if (!value.monthly_mode) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'Choose how the monthly schedule picks its day.',
					path: ['monthly_mode']
				});
			}
			if (value.monthly_mode === 'day_of_month' && value.month_day === null) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'Pick a day of the month.',
					path: ['month_day']
				});
			}
			if (
				value.monthly_mode === 'day_of_week' &&
				(value.ordinal_week === null || value.ordinal_weekday === null)
			) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'Pick which weekday of the month.',
					path: ['ordinal_week']
				});
			}
		}
		if (
			value.end_mode === 'after' &&
			(value.duration_count === null || value.duration_unit === null)
		) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Say how long this schedule runs for.',
				path: ['duration_count']
			});
		}
		if (value.end_mode === 'on') {
			if (!value.end_date) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'Pick the date this schedule ends.',
					path: ['end_date']
				});
			} else if (value.end_date < value.start_date) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'The end date has to come after the start date.',
					path: ['end_date']
				});
			}
		}
		if (value.end_time && !value.start_time) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Set a start time before an end time.',
				path: ['start_time']
			});
		}
		if (value.start_time && value.end_time && value.end_time <= value.start_time) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'The end time has to come after the start time.',
				path: ['end_time']
			});
		}
		if (value.all_day && (value.start_time || value.end_time)) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'An anytime schedule carries no start or end time.',
				path: ['all_day']
			});
		}
	});

export type JobRecurrenceInput = z.infer<typeof jobRecurrenceSchema>;

// The count shown above the end-date controls while someone is still typing. The rule alone: no job exists
// yet, and the answer is arithmetic on the dates in front of them.
export const previewJobRecurrenceSchema = z.object({ recurrence: jobRecurrenceSchema });

export const createJobSchema = z
	.object({
		client_id: z.string().uuid('Choose a client to continue.'),
		property_id: z.string().uuid('Choose the property this job is at.'),
		title: z
			.string()
			.trim()
			.min(2, 'Give this job a title.')
			.max(160, 'That title is too long. Keep it under 160 characters.'),
		instructions: z
			.string()
			.trim()
			.max(4000, 'Those instructions are too long.')
			.nullish()
			.transform((value) => value || null),
		invoice_on_close: z.boolean().default(true),
		// One-off work is the visits a person typed; recurring work is generated from a rule; as-needed work is a
		// recurring agreement that deliberately starts with neither. Type is fixed at creation, so this is the
		// only place it is ever set.
		job_type: z.enum(JOB_TYPES).default('one_off'),
		is_as_needed: z.boolean().default(false),
		recurrence: jobRecurrenceSchema.nullish().transform((value) => value ?? null),
		lines: z
			.array(jobScopeLineSchema)
			.max(JOB_LINE_MAX, `A job can hold up to ${JOB_LINE_MAX} lines.`),
		visits: z
			.array(jobVisitSchema)
			.max(JOB_VISIT_MAX, `A one-off job is created with up to ${JOB_VISIT_MAX} visits.`)
			.default([]),
		// The fingerprint of what the person was looking at when they pressed the button. A retry carrying the
		// same key and the same fingerprint gets the first job back; a changed one is a conflict.
		idempotency_key: z.string().uuid('Start a new action and try again.'),
		request_hash: z
			.string()
			.trim()
			.min(1, 'Reload the form and try again.')
			.max(200, 'Reload the form and try again.')
	})
	// The three shapes a new job can have, each refused on the control the person was actually using. The
	// command checks the same three; this only means they hear about it as a form error first.
	.superRefine((value, context) => {
		if (value.job_type === 'one_off') {
			if (value.is_as_needed || value.recurrence) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'A one-off job does not repeat.',
					path: ['job_type']
				});
			}
			if (value.visits.length === 0) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'A job needs at least one visit.',
					path: ['visits']
				});
			}
			return;
		}

		if (value.is_as_needed) {
			if (value.recurrence || value.visits.length > 0) {
				context.addIssue({
					code: z.ZodIssueCode.custom,
					message: 'An as-needed job starts with no schedule and no visits.',
					path: ['visits']
				});
			}
			return;
		}

		if (!value.recurrence) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Set the schedule this job repeats on.',
				path: ['recurrence']
			});
		}
		if (value.visits.length > 0) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'A repeating job builds its own visits from the schedule.',
				path: ['visits']
			});
		}
	});

export type CreateJobInput = z.infer<typeof createJobSchema>;

// --- Editing a job's details ------------------------------------------------------------------------------

// The only two fields Part 8 lets the detail page stage and save: the job's title and its instructions.
// Scope lines, visits, and billing each have their own command in later parts. `expected_revision` is the
// revision the browser last read; a stale one is refused so two people editing a job cannot silently
// overwrite each other.
export const updateJobDetailsSchema = z.object({
	expected_revision: z.number().int().min(0),
	title: z
		.string()
		.trim()
		.min(2, 'Give this job a title.')
		.max(160, 'That title is too long. Keep it under 160 characters.'),
	instructions: z
		.string()
		.trim()
		.max(4000, 'Those instructions are too long.')
		.nullish()
		.transform((value) => value || null)
});

export type UpdateJobDetailsInput = z.infer<typeof updateJobDetailsSchema>;

// --- Closing and reopening a job (Part 13a) ---------------------------------------------------------------

// Both close_job and reopen_job need only the revision the browser last read, the same shape delete_job_visit
// already uses for a single-row transition.
export const jobLifecycleSchema = z.object({
	expected_revision: z.number().int().min(0)
});

export type JobLifecycleInput = z.infer<typeof jobLifecycleSchema>;

// --- Pricing and billing a job that already exists (Part 11a) ---------------------------------------------

// The whole scope in one save, the same all-or-nothing replacement a quote's lines use. Positions come from
// the browser's order; the command renumbers them from zero so a gap or a duplicate cannot survive a save.
export const replaceJobLinesSchema = z.object({
	expected_revision: z.number().int().min(0),
	lines: z
		.array(jobScopeLineSchema)
		.max(JOB_LINE_MAX, `A job can hold up to ${JOB_LINE_MAX} lines.`)
});

// The three billing decisions stay separate on purpose (contract, "Billing timing and collection, kept
// separate"). These are the first two — how the work is priced, and when we remind ourselves to invoice.
// How the money is collected is Payments' decision and is not settable from here at all. Both lists come
// from the quote conversion schema that already had to name them; one list, so the two screens cannot drift.
export const setJobBillingSchema = z.object({
	expected_revision: z.number().int().min(0),
	price_basis: z.enum(JOB_PRICE_BASES),
	billing_timing: z.enum(JOB_BILLING_TIMINGS)
});

// One discount on the job. A null type removes it, which is why the name and value are optional here and the
// pairing is checked instead of each field on its own.
export const setJobDiscountSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		type: z.enum(['fixed', 'percentage']).nullish(),
		name: z
			.string()
			.trim()
			.max(80, 'That discount name is too long.')
			.nullish()
			.transform((value) => value || null),
		value: z.number().int().min(0).max(MINOR_UNIT_MAX).nullish()
	})
	.refine((body) => !body.type || Boolean(body.name), {
		message: 'Give this discount a name the customer will recognize.',
		path: ['name']
	})
	.refine((body) => !body.type || typeof body.value === 'number', {
		message: 'Enter how much comes off.',
		path: ['value']
	})
	.refine((body) => body.type !== 'percentage' || (body.value ?? 0) <= 10_000, {
		message: 'A percentage discount is between 0 and 100 percent.',
		path: ['value']
	});

// --- Invoice reminders (Part 11b) -------------------------------------------------------------------------

// One custom-date invoice reminder as the detail page adds it. The date is the only required field; the
// note is an optional line for the office ("bill with the March statement"). The database's own 200-char
// check is mirrored here so an over-long note is a field error rather than a raw constraint violation.
export const addJobInvoiceReminderSchema = z.object({
	due_on: z.string().regex(ISO_DATE, 'Pick a date for this reminder.'),
	note: z
		.string()
		.trim()
		.max(200, 'Keep the note under 200 characters.')
		.nullish()
		.transform((value) => value || null)
});

export type AddJobInvoiceReminderInput = z.infer<typeof addJobInvoiceReminderSchema>;

// Tax resolved the same five ways a quote resolves it — literally the same list, so a job and the quote it
// came from can never offer different options. A saved rate needs its id; a one-off custom rate needs a name
// and a rate, and saving it to the shared list is a separate settings permission the command checks.
export const setJobTaxSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		source: z.enum(QUOTE_TAX_SOURCES, { message: 'Choose a tax option.' }),
		rate_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null),
		custom_name: z
			.string()
			.trim()
			.max(80, 'That tax name is too long.')
			.nullish()
			.transform((value) => value || null),
		custom_rate_basis_points: z.number().int().min(1).max(10_000).nullish(),
		save_as_reusable: z.boolean().default(false)
	})
	.refine((body) => body.source !== 'saved_rate' || Boolean(body.rate_id), {
		message: 'Choose a saved tax rate.',
		path: ['rate_id']
	})
	.refine((body) => body.source !== 'custom' || Boolean(body.custom_name), {
		message: 'Give this tax a name the customer will recognize.',
		path: ['custom_name']
	})
	.refine((body) => body.source !== 'custom' || typeof body.custom_rate_basis_points === 'number', {
		message: 'Enter a tax rate.',
		path: ['custom_rate_basis_points']
	});

// --- Scheduling a job's visits (Part 9) -------------------------------------------------------------------

// Where a visit came from. The create flow and the add-visits action make manual visits; a visit duplicated
// into the same job or added as a return trip carries its own source so the history reads truthfully.
const VISIT_SOURCES = ['manual', 'return', 'duplicated'] as const;

// One visit as the add-visits action describes it: the shared schedule fields, its people, and where it came
// from. No position — the command appends new visits after the job's existing ones.
const addVisitSchema = z
	.object({
		...visitScheduleFields,
		assignee_ids: z.array(z.string().uuid()).max(50).default([]),
		source: z.enum(VISIT_SOURCES).default('manual')
	})
	.superRefine(refineVisitShape);

// Add between one and twenty visits to a job that already exists. The idempotency key and fingerprint let a
// double click or a retried request return the first result instead of adding a second batch.
export const addJobVisitsSchema = z.object({
	visits: z
		.array(addVisitSchema)
		.min(1, 'Add at least one visit.')
		.max(JOB_VISIT_MAX, `Up to ${JOB_VISIT_MAX} visits can be added at once.`),
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
});

export type AddJobVisitsInput = z.infer<typeof addJobVisitsSchema>;

// The whole desired state of one visit, plus the revision the browser last read. The assignee set replaces
// the visit's crew exactly; an empty array clears it.
export const updateJobVisitSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		...visitScheduleFields,
		assignee_ids: z.array(z.string().uuid()).max(50).default([])
	})
	.superRefine(refineVisitShape);

export type UpdateJobVisitInput = z.infer<typeof updateJobVisitSchema>;

// Removing one visit needs only the revision the browser last read, so a stale delete cannot remove a visit
// someone else has since changed.
export const deleteJobVisitSchema = z.object({
	expected_revision: z.number().int().min(0)
});

export type DeleteJobVisitInput = z.infer<typeof deleteJobVisitSchema>;

// Move a batch of visits forward or back by whole days. Zero is not a move; the ten-year ceiling matches the
// command's own guard so an absurd offset is a field error, not a raw constraint violation.
export const moveJobVisitsSchema = z.object({
	visit_ids: z
		.array(z.string().uuid())
		.min(1, 'Choose at least one visit to move.')
		.max(100, 'Up to 100 visits can be moved at once.'),
	day_offset: z
		.number()
		.int('Move visits by whole days.')
		.refine((value) => value !== 0, 'Choose how many days to move the visits.')
		.refine((value) => Math.abs(value) <= 3650, 'Visits can only be moved within ten years.'),
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
});

export type MoveJobVisitsInput = z.infer<typeof moveJobVisitsSchema>;

// Replace a recurring job's repeat rule and rebuild its incomplete visits. The rule is checked by the same
// schema the New Job page uses, so an impossible schedule is a field error on the control the person was
// touching rather than a constraint violation from the rebuild. `expected_revision` is the job revision the
// browser last read; the command refuses a stale one instead of overwriting someone else's change.
export const rescheduleJobVisitsSchema = z.object({
	expected_revision: z.number().int().min(0),
	recurrence: jobRecurrenceSchema,
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
});

export type RescheduleJobVisitsInput = z.infer<typeof rescheduleJobVisitsSchema>;

// Copy one visit's time of day and/or crew onto the job's later incomplete visits. Jobber offers two more
// boxes; ours are the two that act on something this app has. Line items wait for a visit to own its own
// quantities, and the repeat rule belongs to the guarded rebuild above, never to a quiet checkbox.
export const applyVisitToFutureSchema = z
	.object({
		time_of_day: z.boolean().default(false),
		assigned_team: z.boolean().default(false),
		idempotency_key: z.string().uuid('Start a new action and try again.'),
		request_hash: z
			.string()
			.trim()
			.min(1, 'Reload and try again.')
			.max(200, 'Reload and try again.')
	})
	.superRefine((value, context) => {
		if (!value.time_of_day && !value.assigned_team) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Choose at least one setting to apply to the later visits.',
				path: ['time_of_day']
			});
		}
	});

export type ApplyVisitToFutureInput = z.infer<typeof applyVisitToFutureSchema>;
