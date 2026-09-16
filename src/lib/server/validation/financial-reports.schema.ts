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
