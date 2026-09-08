import { z } from 'zod';

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
	photo_attachment_ids: z
		.array(z.string().uuid())
		.max(300, 'That is too many photos to add.')
		.default([]),
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
