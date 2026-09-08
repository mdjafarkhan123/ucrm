import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { issueJobReportAccessLinkSchema } from '$lib/server/validation/job-reports.schema';
import { jobReportWriteError } from '$lib/server/jobs/report-errors';
import {
	createJobReportAccessToken,
	jobReportAccessLinkUrl
} from '$lib/server/jobs/report-access-links';

// Making the customer's door by hand -- the "Copy work report link" press, the same shape as an invoice's own
// customer link. The token is generated here, in Node, and the database is handed only its SHA-256, so the
// raw link exists exactly once, in this response. Asking twice does not leave two working doors: the write
// function rotates the job's older links in the same transaction.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown = {};
	const raw = await event.request.text();
	if (raw.trim().length > 0) {
		try {
			body = JSON.parse(raw);
		} catch {
			return validationError({ form: 'Request body must be valid JSON.' });
		}
	}

	const parsed = issueJobReportAccessLinkSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { token, tokenHash } = createJobReportAccessToken();

	const { data, error } = await event.locals.supabase.rpc('issue_job_report_access_link', {
		target_job_id: event.params.id,
		supplied_token_hash: tokenHash
	});

	if (error) return jobReportWriteError(error);
	return json(
		{ ...(data as Record<string, unknown>), url: jobReportAccessLinkUrl(event.url.origin, token) },
		{ headers: NO_STORE_HEADERS }
	);
};
