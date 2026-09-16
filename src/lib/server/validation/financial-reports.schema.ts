import { z } from 'zod';

export const FINANCIAL_REPORT_PAGE_SIZE_DEFAULT = 50;
export const FINANCIAL_REPORT_PAGE_SIZE_MAX = 100;

export const invoiceSalesReportQuerySchema = z
	.object({
		from: z.iso.date({ error: 'Pick a valid start date.' }),
		to: z.iso.date({ error: 'Pick a valid end date.' }),
		cursor: z.string().min(3).max(100).optional(),
		limit: z.coerce
			.number()
			.int()
			.min(1)
			.max(FINANCIAL_REPORT_PAGE_SIZE_MAX)
			.default(FINANCIAL_REPORT_PAGE_SIZE_DEFAULT),
		direction: z.enum(['asc', 'desc']).default('desc')
	})
	.refine((query) => query.from < query.to, {
		message: 'The end date must be after the start date.',
		path: ['to']
	});

export const clientAgingReportQuerySchema = z.object({
	asOf: z.iso.date({ error: 'Pick a valid aging date.' }),
	cursor: z.string().min(3).max(500).optional(),
	limit: z.coerce
		.number()
		.int()
		.min(1)
		.max(FINANCIAL_REPORT_PAGE_SIZE_MAX)
		.default(FINANCIAL_REPORT_PAGE_SIZE_DEFAULT),
	direction: z.enum(['asc', 'desc']).default('asc')
});

export const paymentEventsReportQuerySchema = z
	.object({
		from: z.iso.date({ error: 'Pick a valid start date.' }),
		to: z.iso.date({ error: 'Pick a valid end date.' }),
		cursor: z.string().min(3).max(500).optional(),
		limit: z.coerce
			.number()
			.int()
			.min(1)
			.max(FINANCIAL_REPORT_PAGE_SIZE_MAX)
			.default(FINANCIAL_REPORT_PAGE_SIZE_DEFAULT),
		direction: z.enum(['asc', 'desc']).default('desc')
	})
	.refine((query) => query.from < query.to, {
		message: 'The end date must be after the start date.',
		path: ['to']
	});

export const paymentAllocationsReportQuerySchema = paymentEventsReportQuerySchema;
export const depositCreditsReportQuerySchema = paymentEventsReportQuerySchema;
export const invoiceTaxReportQuerySchema = invoiceSalesReportQuerySchema;
export const uninvoicedWorkReportQuerySchema = invoiceSalesReportQuerySchema;
export const jobProfitabilityReportQuerySchema = invoiceSalesReportQuerySchema;
export const salesOutcomesReportQuerySchema = paymentEventsReportQuerySchema;
export const timeEntriesReportQuerySchema = paymentEventsReportQuerySchema;

// The accounting package downloads directly, so one package covers at most a year; a longer history is two
// downloads. Counted in whole days between the two ISO dates.
export const FINANCIAL_EXPORT_MAX_DAYS = 366;

export const financialExportQuerySchema = z
	.object({
		from: z.iso.date({ error: 'Pick a valid start date.' }),
		to: z.iso.date({ error: 'Pick a valid end date.' })
	})
	.refine((query) => query.from < query.to, {
		message: 'The end date must be after the start date.',
		path: ['to']
	})
	.refine(
		(query) =>
			(Date.parse(query.to) - Date.parse(query.from)) / 86_400_000 <= FINANCIAL_EXPORT_MAX_DAYS,
		{ message: 'One download covers up to one year. Split a longer period.', path: ['to'] }
	);
