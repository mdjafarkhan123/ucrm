import { z } from 'zod';

// One place in the report: a photo on its own, or a before/after pair of two different photos.
const layoutItemSchema = z.union([
	z.strictObject({ file_id: z.string().uuid() }),
	z
		.strictObject({ before_file_id: z.string().uuid(), after_file_id: z.string().uuid() })
		.refine((pair) => pair.before_file_id !== pair.after_file_id, {
			message: 'A before/after pair needs two different photos.'
		})
]);

const layoutSectionSchema = z.strictObject({
	heading: z
		.string()
		.trim()
		.min(1, 'Give every heading a name.')
		.max(80, 'Keep each heading under 80 characters.'),
	note: z
		.string()
		.trim()
		.max(1000, 'Keep each heading note under 1000 characters.')
		.nullish()
		.transform((value) => value || null),
	items: z.array(layoutItemSchema).max(300)
});

// Photos above the first heading, then each heading with its photos. Each photo appears at most once, and
// there are at most 300 in all -- the command re-checks both, and that every photo is this job's.
const jobReportLayoutSchema = z
	.strictObject({
		top: z.array(layoutItemSchema).max(300),
		sections: z.array(layoutSectionSchema).max(50, 'That is too many headings for one report.')
	})
	.superRefine((layout, context) => {
		const ids = [layout.top, ...layout.sections.map((section) => section.items)]
			.flat()
			.flatMap((item) =>
				'file_id' in item ? [item.file_id] : [item.before_file_id, item.after_file_id]
			);
		if (ids.length > 300) {
			context.addIssue({ code: 'custom', message: 'That is too many photos to add.' });
		}
		if (new Set(ids).size !== ids.length) {
			context.addIssue({ code: 'custom', message: 'A photo can appear only once in a report.' });
		}
	});

// The whole work-report selection, replaced in one call by `save_job_report`. Every relationship named here
// is re-checked by the command against the job itself, so this only shapes the request -- a bad photo or
// checklist id surfaces as a form error from the database rather than a silent drop.
export const saveJobReportSchema = z.strictObject({
	include_service_details: z.boolean(),
	include_price: z.boolean(),
	signature_id: z
		.string()
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	summary: z
		.string()
		.trim()
		.max(2000, 'That summary is too long. Keep it under 2000 characters.')
		.nullish()
		.transform((value) => value || null),
	layout: jobReportLayoutSchema.default({ top: [], sections: [] }),
	checklist_selections: z
		.array(
			z.object({
				visit_id: z.string().uuid(),
				item_id: z.string().uuid()
			})
		)
		.max(500, 'That is too many checklist answers to add.')
		.default([])
});

export type SaveJobReportInput = z.infer<typeof saveJobReportSchema>;

// Copying the work-report link takes no body: which job is in the URL, and the recipient is the client's own
// email. Strict so an unexpected field is refused rather than dropped.
export const issueJobReportAccessLinkSchema = z.strictObject({});
