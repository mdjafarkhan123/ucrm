import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { saveJobReportSchema } from '$lib/server/validation/job-reports.schema';
import { jobReportReadError, jobReportWriteError } from '$lib/server/jobs/report-errors';

// The editor's own read and write. Both `job_report_state` and `save_job_report` decide jobs.edit for
// themselves and re-check every relationship against the job, so this route only shapes the request and
// maps what comes back -- the same division every other job command already uses.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('job_report_state', {
		target_job_id: event.params.id
	});
	if (error) return jobReportReadError(error);

	return json(data, { headers: PRIVATE_READ_HEADERS });
};

export const PUT: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = saveJobReportSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('save_job_report', {
		target_job_id: event.params.id,
		new_include_service_details: parsed.data.include_service_details,
		new_include_price: parsed.data.include_price,
		new_signature_id: parsed.data.signature_id ?? undefined,
		new_summary: parsed.data.summary ?? undefined,
		photo_attachment_ids: parsed.data.photo_attachment_ids,
		checklist_selections: parsed.data.checklist_selections
	});
	if (error) return jobReportWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
