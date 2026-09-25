// The browser's view of the File catalog: the reads the workspace draws from, then the upload handshake and
// the manage actions it writes with.

/**
 * The smart views in the File Manager rail. `folder` is one user folder, named by `folderId`, and `label`
 * the photos carrying one label, named by `labelId`; `on_record`
 * is the picker's first section — the files already on the record it was opened from — and is the only view
 * that reads `entityType`/`entityId`.
 */
export type FileView =
	| 'all'
	| 'recent'
	| 'photos'
	| 'documents'
	| 'not_attached'
	| 'trash'
	| 'folder'
	| 'label'
	| 'on_record';

/** The CRM records a File can be attached to. Matches the file_links entity_type constraint. */
export type FileEntityType =
	| 'client'
	| 'property'
	| 'request'
	| 'quote'
	| 'job_expense'
	| 'job'
	| 'visit'
	| 'invoice'
	| 'organization'
	| 'marketing_campaign';

export type FileKind = 'image' | 'video' | 'document';
export type FileProcessingState = 'pending' | 'available' | 'failed' | 'quarantined';

export type FileListFilters = {
	view: FileView;
	folderId: string;
	/** The rail's label, when `view` is `label`. */
	labelId?: string;
	search: string;
	/** The picker's record context. Part of the key, so two pickers never share one cached section. */
	entityType?: FileEntityType;
	entityId?: string;
	/** The picker's rule: only files that have passed their checks can be attached to anything. */
	attachable?: boolean;
	/** Overrides the server's default page size. Not part of any cached query key today. */
	limit?: number;
};

export type FileListItem = {
	id: string;
	display_name: string;
	mime_type: string;
	kind: FileKind;
	size_bytes: number;
	has_thumbnail: boolean;
	folder_id: string | null;
	folder_name: string | null;
	origin_type: string;
	origin_id: string | null;
	processing_state: FileProcessingState;
	uploaded_by: string | null;
	uploaded_by_name: string | null;
	created_at: string;
	trashed_at: string | null;
	/** Distinct records using this file that the reader may view. Never a raw link-row total. */
	usage_count: number;
	/** A photo's one-line description. Always null on a document. */
	caption: string | null;
};

export type FileListPage = {
	files: FileListItem[];
	/** Null means this was the last page. Keyset paginated, so there is no page number to jump to. */
	next_cursor: string | null;
	can_manage: boolean;
	can_trash: boolean;
	/** May share chosen files with a customer by link (files.share). */
	can_share: boolean;
	/** The business has made at least one share, so the rail offers "Shared with customers". First page only. */
	has_shares?: boolean;
};

export type FileUsageRow = {
	id: string;
	entity_type: string;
	entity_id: string;
	role: string;
	protected: boolean;
	/** A customer already received this exact use (a published quote, a live work report link). Trashing it needs their warning. */
	customer_received: boolean;
	title: string | null;
	context: string | null;
	status: string | null;
	/** Which record type the row opens; a visit and a job expense both open their job. */
	link_type: string;
	link_id: string;
	created_at: string;
};

/** One entry of the organization's photo label list (Before, After, Damage...). */
export type FileLabel = { id: string; name: string };

export type FileDetail = {
	file: Omit<FileListItem, 'usage_count'> & {
		has_thumbnail: boolean;
		labels: FileLabel[];
	};
	usage: FileUsageRow[];
	usage_next_cursor: string | null;
	can_manage: boolean;
	can_trash: boolean;
	can_share: boolean;
	/** May change this photo's caption and labels: files.manage, or a writer on a job the photo is on. */
	can_describe: boolean;
	/** The Clients holding a live customer link to this file, one row each. Empty for a non-sharer. */
	shared_with: FileSharedWith[];
};

export type FileSharedWith = {
	client_id: string;
	/** Null when this member may not see that Client. */
	client_name: string | null;
	/** How many live links that Client holds to this file. */
	share_count: number;
	/** The latest of those links' end dates. */
	expires_at: string;
};

export type FileFolder = { id: string; name: string; file_count: number };

export const filesListKey = (filters: FileListFilters) => ['files', 'list', filters] as const;
export const fileDetailKey = (fileId: string) => ['files', 'detail', fileId] as const;
export const fileFoldersKey = ['files', 'folders'] as const;
export const fileLabelsKey = ['files', 'labels'] as const;
export const fileSharesKey = ['files', 'shares', 'list'] as const;
export const fileShareDetailKey = (shareId: string) =>
	['files', 'shares', 'detail', shareId] as const;

// Carries the status the server refused with, so the query client stops retrying a 403/404 — the answer
// never changes — and the page can say "no access" instead of blaming the connection.
export type FileReadError = Error & { status: number };

async function readError(response: Response, fallback: string): Promise<FileReadError> {
	const result = await response.json().catch(() => ({}) as { error?: string });
	const error = new Error(result.error ?? fallback) as FileReadError;
	error.status = response.status;
	return error;
}

export async function fetchFiles(filters: FileListFilters, cursor?: string): Promise<FileListPage> {
	const params = new URLSearchParams();
	if (filters.view !== 'all') params.set('view', filters.view);
	if (filters.view === 'folder' && filters.folderId) params.set('folder_id', filters.folderId);
	if (filters.view === 'label' && filters.labelId) params.set('label_id', filters.labelId);
	if (filters.search) params.set('search', filters.search);
	if (filters.view === 'on_record' && filters.entityType && filters.entityId) {
		params.set('entity_type', filters.entityType);
		params.set('entity_id', filters.entityId);
	}
	if (filters.attachable) params.set('attachable', '1');
	if (filters.limit) params.set('limit', String(filters.limit));
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/files?${params.toString()}`);
	if (!response.ok) throw await readError(response, 'Files could not be loaded.');
	return response.json();
}

export async function fetchFile(fileId: string): Promise<FileDetail> {
	const response = await fetch(`/api/files/${fileId}`);
	if (!response.ok) throw await readError(response, 'That file could not be loaded.');
	return response.json();
}

export async function fetchFileFolders(): Promise<FileFolder[]> {
	const response = await fetch('/api/files/folders');
	if (!response.ok) throw await readError(response, 'Folders could not be loaded.');
	const result = await response.json();
	return result.folders;
}

/** The inline picture for a tile or the panel preview. Never a presigned link — those expire in minutes. */
export function fileImageUrl(fileId: string, size: 'thumb' | 'full' = 'full') {
	return size === 'thumb' ? `/api/files/${fileId}/view?size=thumb` : `/api/files/${fileId}/view`;
}

/** Mints a short-lived download link and hands it to the browser. */
export async function downloadFile(fileId: string): Promise<void> {
	const response = await fetch(`/api/files/${fileId}/download`);
	if (!response.ok) throw await readError(response, 'That file could not be downloaded.');
	const result = await response.json();
	window.location.href = result.download_url;
}

// --- Writing ------------------------------------------------------------------------------------------

type WriteErrorBody = { error?: string; field_errors?: Record<string, string> };

// A write's refusal is usually a sentence the contractor is meant to read — "you already have a folder with
// that name", "the customer already received this" — so the first field error is preferred over the generic
// "please review the highlighted fields" wrapper around it.
async function writeError(response: Response, fallback: string): Promise<FileReadError> {
	const result: WriteErrorBody = await response.json().catch(() => ({}));
	const fieldError = result.field_errors ? Object.values(result.field_errors)[0] : undefined;
	const error = new Error(fieldError ?? result.error ?? fallback) as FileReadError;
	error.status = response.status;
	return error;
}

async function writeJson<T>(
	url: string,
	method: string,
	body?: unknown,
	fallback = 'That did not save.'
) {
	const response = await fetch(url, {
		method,
		...(body === undefined
			? {}
			: { headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
	});
	if (!response.ok) throw await writeError(response, fallback);
	return response.json() as Promise<T>;
}

export type FileUploadTarget = {
	/** Where this file is entering UCRM. The library's own uploads are `file_manager` with no record. */
	originType: string;
	originId?: string | null;
	folderId?: string | null;
	/** The file_links role the upload will be linked to its record with. Defaults to a plain 'attachment'. */
	originRole?: 'attachment' | 'line_photo' | 'logo' | 'campaign_image';
};

export type StartedUpload = { file: { id: string }; upload_url: string };

export function startFileUpload(file: File, target: FileUploadTarget) {
	return writeJson<StartedUpload>(
		'/api/files/uploads',
		'POST',
		{
			file_name: file.name,
			mime_type: file.type,
			size_bytes: file.size,
			origin_type: target.originType,
			origin_id: target.originId ?? null,
			folder_id: target.folderId ?? null,
			...(target.originRole ? { origin_role: target.originRole } : {})
		},
		'That file could not be uploaded.'
	);
}

export function finishFileUpload(fileId: string) {
	return writeJson<{ file: unknown }>(
		`/api/files/uploads/${fileId}/complete`,
		'POST',
		{},
		'That upload could not be finished.'
	);
}

export function renameFile(fileId: string, displayName: string) {
	return writeJson<{ file: unknown }>(
		`/api/files/${fileId}`,
		'PATCH',
		{ display_name: displayName },
		'That file could not be renamed.'
	);
}

/** Null is a real answer: it takes the file out of every folder. */
export function moveFile(fileId: string, folderId: string | null) {
	return writeJson<{ file: unknown }>(
		`/api/files/${fileId}`,
		'PATCH',
		{ folder_id: folderId },
		'That file could not be moved.'
	);
}

/** Caption and labels together, because the editor saves them as one decision. */
export function describeFile(fileId: string, caption: string, labelIds: string[]) {
	return writeJson<{ file: unknown }>(
		`/api/files/${fileId}`,
		'PATCH',
		{ caption, label_ids: labelIds },
		'That caption and labels could not be saved.'
	);
}

export async function fetchFileLabels(): Promise<FileLabel[]> {
	const response = await fetch('/api/files/labels');
	if (!response.ok) throw await readError(response, 'Your labels could not be loaded.');
	const result = (await response.json()) as { labels: FileLabel[] };
	return result.labels;
}

export async function createFileLabel(name: string) {
	const result = await writeJson<{ label: FileLabel }>(
		'/api/files/labels',
		'POST',
		{ name },
		'That label could not be created.'
	);
	return result.label;
}

export async function renameFileLabel(labelId: string, name: string) {
	const result = await writeJson<{ label: FileLabel }>(
		`/api/files/labels/${labelId}`,
		'PATCH',
		{ name },
		'That label could not be renamed.'
	);
	return result.label;
}

export async function deleteFileLabel(labelId: string) {
	const response = await fetch(`/api/files/labels/${labelId}`, { method: 'DELETE' });
	if (!response.ok) throw await writeError(response, 'That label could not be removed.');
}

// SQLSTATE P0412 comes back as this exact status when a customer already received the file and the
// caller has not ticked "I understand" yet — the dialog reads it to ask again instead of showing a
// dead-end error.
export type TrashRequiresAcknowledgementError = FileReadError & { requiresAcknowledgement: true };

export async function trashFile(fileId: string, acknowledgeCustomerCopies = false) {
	try {
		return await writeJson<{ file: unknown }>(
			`/api/files/${fileId}/trash`,
			'POST',
			{ acknowledge_customer_copies: acknowledgeCustomerCopies },
			'That file could not be moved to Trash.'
		);
	} catch (error) {
		if (error instanceof Error && (error as FileReadError).status === 409) {
			(error as TrashRequiresAcknowledgementError).requiresAcknowledgement = true;
		}
		throw error;
	}
}

export function restoreFile(fileId: string) {
	return writeJson<{ file: unknown }>(
		`/api/files/${fileId}/restore`,
		'POST',
		{},
		'That file could not be restored.'
	);
}

export type FileAttachResult = {
	attached_count: number;
	attached: string[];
	/** The files that could not be attached, each with the sentence to show the contractor. */
	refused: { file_id: string; reason: string }[];
};

/** Adds existing Files to one record. Never copies anything: each one becomes another use of the same File. */
export function attachFilesToRecord(
	fileIds: string[],
	entityType: FileEntityType,
	entityId: string
) {
	return writeJson<FileAttachResult>(
		'/api/files/links',
		'POST',
		{ file_ids: fileIds, entity_type: entityType, entity_id: entityId },
		'Those files could not be attached.'
	);
}

/** Takes one File off one record. The File, its stored object, and its other uses are untouched. */
export function detachFileFromRecord(fileId: string, entityType: FileEntityType, entityId: string) {
	return writeJson<{ removed: boolean }>(
		'/api/files/links',
		'DELETE',
		{ file_id: fileId, entity_type: entityType, entity_id: entityId },
		'That file could not be taken off this record.'
	);
}

/** The three lengths a customer share can last. A share never gets longer once made. */
export type FileShareDays = 7 | 30 | 90;

export type CreatedFileShare = {
	share: {
		id: string;
		client_id: string;
		client_name: string;
		file_count: number;
		issued_at: string;
		expires_at: string;
	};
	/** The customer link. This response is the only time it exists anywhere; it is not stored. */
	url: string;
};

/** Makes one customer link to exactly these files. Their names are fixed on the customer's page from now. */
export function createFileShare(fileIds: string[], clientId: string, days: FileShareDays) {
	return writeJson<CreatedFileShare>(
		'/api/files/shares',
		'POST',
		{ file_ids: fileIds, client_id: clientId, days },
		'That link could not be made.'
	);
}

export type FileShareListItem = {
	id: string;
	client_id: string;
	/** Null when this member may not see that Client. */
	client_name: string | null;
	file_count: number;
	issued_at: string;
	issued_by_name: string | null;
	expires_at: string;
	revoked_at: string | null;
	first_viewed_at: string | null;
	last_viewed_at: string | null;
	view_count: number;
};

export type FileShareListPage = { shares: FileShareListItem[]; next_cursor: string | null };

export type FileShareDetail = Omit<FileShareListItem, 'file_count' | 'issued_by_name'> & {
	files: {
		file_id: string;
		/** The name the customer sees, fixed when the file was shared. */
		shared_name: string;
		/** Null when this member's own file access does not reach it. */
		file: {
			id: string;
			display_name: string;
			mime_type: string;
			kind: FileKind;
			size_bytes: number;
			has_thumbnail: boolean;
			processing_state: FileProcessingState;
			trashed_at: string | null;
		} | null;
	}[];
};

export type FileShareState = 'active' | 'expired' | 'off';

/** Turned off wins over expired: a link stopped early reads as a decision someone made. */
export function fileShareState(share: {
	revoked_at: string | null;
	expires_at: string;
}): FileShareState {
	if (share.revoked_at) return 'off';
	return new Date(share.expires_at).getTime() <= Date.now() ? 'expired' : 'active';
}

export async function fetchFileShares(cursor?: string): Promise<FileShareListPage> {
	const params = new URLSearchParams();
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/files/shares?${params.toString()}`);
	if (!response.ok) throw await readError(response, 'Your shared links could not be loaded.');
	return response.json();
}

export async function fetchFileShare(shareId: string): Promise<FileShareDetail> {
	const response = await fetch(`/api/files/shares/${shareId}`);
	if (!response.ok) throw await readError(response, 'That link could not be loaded.');
	const result = (await response.json()) as { share: FileShareDetail };
	return result.share;
}

/** Stops one customer link for good. More time for the customer means making a new link. */
export function turnOffFileShare(shareId: string) {
	return writeJson<{ share: { id: string; client_id: string; revoked_at: string | null } }>(
		`/api/files/shares/${shareId}/turn-off`,
		'POST',
		{},
		'That link could not be turned off.'
	);
}

export function createFileFolder(name: string) {
	return writeJson<{ folder: FileFolder }>(
		'/api/files/folders',
		'POST',
		{ name },
		'That folder could not be created.'
	);
}

const KILOBYTE = 1024;

export function formatFileSize(bytes: number): string {
	if (bytes < KILOBYTE) return `${bytes} B`;
	const megabytes = bytes / (KILOBYTE * KILOBYTE);
	if (megabytes < 1) return `${Math.round(bytes / KILOBYTE)} KB`;
	return `${megabytes.toFixed(megabytes < 10 ? 1 : 0)} MB`;
}

/** The short, plain word for a file's type — "JPEG", "PDF" — rather than its raw MIME string. */
export function formatFileType(mimeType: string, displayName: string): string {
	const extension = displayName.includes('.') ? displayName.split('.').pop() : null;
	if (extension && extension.length <= 4) return extension.toUpperCase();
	return mimeType.split('/').pop()?.toUpperCase() ?? 'FILE';
}

const ORIGIN_LABELS: Record<string, string> = {
	file_manager: 'Uploaded to Files',
	client: 'Client',
	property: 'Property',
	request: 'Request',
	quote: 'Quote',
	invoice: 'Invoice',
	job: 'Job',
	job_expense: 'Job expense',
	visit: 'Visit',
	marketing_campaign: 'Marketing campaign'
};

export function formatOrigin(originType: string): string {
	return ORIGIN_LABELS[originType] ?? 'Uploaded to Files';
}

const ROLE_LABELS: Record<string, string> = {
	attachment: 'Attachment',
	work_photo: 'Work photo',
	report_photo: 'Work report photo',
	line_photo: 'Line item photo',
	campaign_image: 'Campaign image'
};

export function formatRole(role: string): string {
	return ROLE_LABELS[role] ?? 'Attachment';
}

const USAGE_GROUP_LABELS: Record<string, { singular: string; plural: string }> = {
	client: { singular: 'Client', plural: 'Clients' },
	property: { singular: 'Property', plural: 'Properties' },
	request: { singular: 'Request', plural: 'Requests' },
	quote: { singular: 'Quote', plural: 'Quotes' },
	invoice: { singular: 'Invoice', plural: 'Invoices' },
	job: { singular: 'Job', plural: 'Jobs' },
	visit: { singular: 'Visit', plural: 'Visits' },
	job_expense: { singular: 'Job expense', plural: 'Job expenses' },
	organization: { singular: 'Business logo', plural: 'Business logo' },
	message: { singular: 'Message', plural: 'Messages' },
	marketing_campaign: { singular: 'Marketing campaign', plural: 'Marketing campaigns' }
};

export function usageGroupLabel(entityType: string, count: number): string {
	const labels = USAGE_GROUP_LABELS[entityType];
	if (!labels) return count === 1 ? 'Record' : 'Records';
	return count === 1 ? labels.singular : labels.plural;
}
