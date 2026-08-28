// Email templates: the organization's own copy-on-write library, sourced from Jafar's platform templates
// or written from scratch (Communications Part 6c). See
// docs/contractor-email-contract.md § Templates, snippets, and branding.

export type CommunicationEmailTemplate = {
	id: string;
	folder: string | null;
	name: string;
	subject: string;
	body: string;
	source_template_id: string | null;
	source_version_copied_at: number | null;
	created_at: string;
	updated_at: string;
};

// The list read additionally computes whether the platform template it was copied from has since changed --
// nothing a mutation response needs, since saving, copying, or adopting always leaves a template caught up.
export type CommunicationEmailTemplateListItem = CommunicationEmailTemplate & {
	update_available: boolean;
};

export type CommunicationEmailTemplatePage = {
	items: CommunicationEmailTemplateListItem[];
	next_cursor: string | null;
};

export type EmailTemplateSearch = { folder?: string; search?: string };

export type EmailTemplateDraft = {
	folder: string | null;
	name: string;
	subject: string;
	body: string;
};

export type PlatformEmailTemplate = {
	id: string;
	folder: string | null;
	name: string;
	subject: string;
	body: string;
	version: number;
	copied_template_id: string | null;
	update_available: boolean;
};

export class EmailTemplateWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {}
	) {
		super(message);
		this.name = 'EmailTemplateWriteError';
	}
}

export const communicationEmailTemplatesKey = (query: EmailTemplateSearch = {}) =>
	['communications', 'email-templates', query.folder ?? 'all', query.search ?? ''] as const;

export const communicationEmailTemplateLibraryKey = [
	'communications',
	'email-templates',
	'library'
] as const;

export async function fetchCommunicationEmailTemplates(
	query: EmailTemplateSearch = {},
	cursor?: string
): Promise<CommunicationEmailTemplatePage> {
	const params = new URLSearchParams();
	if (query.folder) params.set('folder', query.folder);
	if (query.search) params.set('search', query.search);
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/communications/email-templates?${params.toString()}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'Email templates could not be loaded.');
	return result as CommunicationEmailTemplatePage;
}

export async function fetchCommunicationEmailTemplateLibrary(): Promise<PlatformEmailTemplate[]> {
	const response = await fetch('/api/communications/email-templates/library');
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'The template library could not be loaded.');
	return (result as { templates: PlatformEmailTemplate[] }).templates;
}

async function saveEmailTemplate(url: string, method: 'POST' | 'PATCH', body: object) {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new EmailTemplateWriteError(
			result.error ?? 'That email template could not be saved.',
			result.field_errors ?? {}
		);
	}
	return (result as { item: CommunicationEmailTemplate }).item;
}

export function createCommunicationEmailTemplate(draft: EmailTemplateDraft) {
	return saveEmailTemplate('/api/communications/email-templates', 'POST', draft);
}

export function copyCommunicationEmailTemplate(
	sourceTemplateId: string,
	folder: string | null = null
) {
	return saveEmailTemplate('/api/communications/email-templates', 'POST', {
		source_template_id: sourceTemplateId,
		folder
	});
}

export function updateCommunicationEmailTemplate(id: string, draft: Partial<EmailTemplateDraft>) {
	return saveEmailTemplate(`/api/communications/email-templates/${id}`, 'PATCH', draft);
}

export async function adoptCommunicationEmailTemplateUpdate(id: string) {
	const response = await fetch(`/api/communications/email-templates/${id}/adopt`, {
		method: 'POST'
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new EmailTemplateWriteError(result.error ?? 'That update could not be adopted.');
	}
	return (result as { item: CommunicationEmailTemplate }).item;
}

export async function deleteCommunicationEmailTemplate(id: string): Promise<void> {
	const response = await fetch(`/api/communications/email-templates/${id}`, { method: 'DELETE' });
	if (!response.ok) {
		const result = await response.json().catch(() => ({}));
		throw new EmailTemplateWriteError(result.error ?? 'That email template could not be deleted.');
	}
}
