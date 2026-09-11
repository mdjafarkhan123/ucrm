import type {
	ChecklistAnswerValue,
	ChecklistItemType,
	ChecklistTemplate,
	JobChecklist,
	VisitChecklist
} from './types';

export type ChecklistApiError = Error & {
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
	) as ChecklistApiError;
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

// --- The Settings library ----------------------------------------------------------------------------

export type ChecklistTemplateDraftItem = {
	label: string;
	item_type: ChecklistItemType;
	required: boolean;
	options?: string[];
};

export type ChecklistTemplateList = { templates: ChecklistTemplate[]; can_manage: boolean };

export const checklistTemplatesKey = (includeArchived = false) =>
	['checklists', 'templates', includeArchived] as const;

export function fetchChecklistTemplates(includeArchived = false) {
	const query = includeArchived ? '?archived=true' : '';
	return requestJson<ChecklistTemplateList>(`/api/settings/checklists${query}`);
}

export function createChecklistTemplate(input: {
	name: string;
	items: ChecklistTemplateDraftItem[];
}) {
	return requestJson<{ id: string }>('/api/settings/checklists', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

export function updateChecklistTemplate(
	id: string,
	input: { name: string; items: ChecklistTemplateDraftItem[] }
) {
	return requestJson<{ id: string; jobs_already_using: number }>(`/api/settings/checklists/${id}`, {
		method: 'PATCH',
		body: JSON.stringify(input)
	});
}

export function setChecklistTemplateArchived(id: string, archived: boolean) {
	return requestJson<{ id: string; archived: boolean }>(`/api/settings/checklists/${id}`, {
		method: 'POST',
		body: JSON.stringify({ archived })
	});
}

// --- A job's checklists ------------------------------------------------------------------------------

export type JobChecklistList = { checklists: JobChecklist[]; can_edit: boolean };

export const jobChecklistsKey = (jobId: string) => ['checklists', 'job', jobId] as const;

export function fetchJobChecklists(jobId: string) {
	return requestJson<JobChecklistList>(`/api/jobs/${jobId}/checklists`);
}

export function attachJobChecklist(jobId: string, templateId: string) {
	return requestJson<{ id: string; question_count: number }>(`/api/jobs/${jobId}/checklists`, {
		method: 'POST',
		body: JSON.stringify({ template_id: templateId })
	});
}

export function removeJobChecklist(jobId: string, checklistId: string) {
	return requestJson<{ id: string; answers_removed: number }>(
		`/api/jobs/${jobId}/checklists/${checklistId}`,
		{ method: 'DELETE' }
	);
}

// --- One visit's answers -----------------------------------------------------------------------------

export type VisitChecklistRows = {
	checklists: VisitChecklist[];
	outstanding_required: number;
	can_answer: boolean;
};

export const visitChecklistsKey = (visitId: string) => ['checklists', 'visit', visitId] as const;

export function fetchVisitChecklists(jobId: string, visitId: string) {
	return requestJson<VisitChecklistRows>(`/api/jobs/${jobId}/visits/${visitId}/checklists`);
}

/** Only the questions in `answers` are touched; a null or empty value clears that one question. */
export function saveVisitChecklistAnswers(
	jobId: string,
	visitId: string,
	answers: { item_id: string; value: ChecklistAnswerValue }[]
) {
	return requestJson<{ saved: number; cleared: number }>(
		`/api/jobs/${jobId}/visits/${visitId}/checklists`,
		{ method: 'PATCH', body: JSON.stringify({ answers }) }
	);
}
