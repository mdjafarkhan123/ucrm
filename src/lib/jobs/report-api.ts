import type { JobReportState } from './report-types';

export type JobReportApiError = Error & {
	fieldErrors?: Record<string, string>;
	reason?: string;
	status?: number;
};

async function throwApiError(response: Response): Promise<never> {
	const result = await response
		.json()
		.catch(
			() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
		);
	const error = new Error(
		result.error ?? 'That request could not be completed.'
	) as JobReportApiError;
	error.fieldErrors = result.field_errors ?? {};
	error.reason = result.reason;
	error.status = response.status;
	throw error;
}

async function requestJson<T>(input: string, init?: RequestInit): Promise<T> {
	const response = await fetch(input, {
		...init,
		headers: init?.body ? { 'content-type': 'application/json', ...init.headers } : init?.headers
	});
	if (!response.ok) return throwApiError(response);
	return response.json();
}

export const jobReportStateKey = (jobId: string) => ['jobs', 'report', jobId] as const;

export function fetchJobReportState(jobId: string) {
	return requestJson<JobReportState>(`/api/jobs/${jobId}/report`);
}

export type SaveJobReportInput = {
	include_service_details: boolean;
	include_price: boolean;
	signature_id: string | null;
	summary: string | null;
	photo_attachment_ids: string[];
	checklist_selections: { visit_id: string; item_id: string }[];
};

export function saveJobReport(jobId: string, input: SaveJobReportInput) {
	return requestJson<{ job_id: string; has_content: boolean }>(`/api/jobs/${jobId}/report`, {
		method: 'PUT',
		body: JSON.stringify(input)
	});
}

export type JobReportAccessLink = {
	job_id: string;
	job_report_access_link_id: string;
	recipient_name: string | null;
	recipient_email: string;
	issued_at: string;
	expires_at: string | null;
	url: string;
};

// The customer's own link, for "Copy work report link". The raw link comes back exactly once, in this
// response; asking again rotates the old one off, which is what staff mean by "send them the link again".
export function issueJobReportAccessLink(jobId: string) {
	return requestJson<JobReportAccessLink>(`/api/jobs/${jobId}/report/access-links`, {
		method: 'POST',
		body: '{}'
	});
}
