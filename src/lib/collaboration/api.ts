import type { Tables } from '$lib/database.types';

// Quotes/Jobs/Invoices become linkable later without changing anything else here.
export type EntityType = 'client' | 'property' | 'request' | 'quote';

export type ApiError = Error & { fieldErrors?: Record<string, string> };

async function throwApiError(response: Response): Promise<never> {
	const result = await response
		.json()
		.catch(() => ({}) as { error?: string; field_errors?: Record<string, string> });
	const error = new Error(result.error ?? 'That request could not be completed.') as ApiError;
	error.fieldErrors = result.field_errors ?? {};
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

function entityQuery(entityType: EntityType, entityId: string) {
	return new URLSearchParams({ entity_type: entityType, entity_id: entityId }).toString();
}

// --- Notes -----------------------------------------------------------------------------------------------

export type Note = Tables<'notes'> & { links: Tables<'note_links'>[] };

/**
 * One staged note change. A detail page collects these while the office works and writes them only when its
 * action bar saves, so nothing on the page reaches the server on its own. `key` is a local id for a note that
 * does not exist yet; `id` is a saved note's real id.
 */
export type NoteChange =
	| { kind: 'create'; key: string; body: string }
	| { kind: 'update'; id: string; body: string }
	| { kind: 'pin'; id: string; pinned: boolean }
	| { kind: 'delete'; id: string };

export const notesKey = (entityType: EntityType, entityId: string) =>
	['collaboration', 'notes', entityType, entityId] as const;

export async function fetchNotes(entityType: EntityType, entityId: string) {
	const { notes } = await requestJson<{ notes: Note[] }>(
		`/api/notes?${entityQuery(entityType, entityId)}`
	);
	return notes;
}

export async function createNote(input: {
	entityType: EntityType;
	entityId: string;
	body: string;
	pinned?: boolean;
}) {
	const { note } = await requestJson<{ note: Note }>('/api/notes', {
		method: 'POST',
		body: JSON.stringify({
			entity_type: input.entityType,
			entity_id: input.entityId,
			body: input.body,
			pinned: input.pinned ?? false
		})
	});
	return note;
}

export async function updateNote(input: {
	id: string;
	entityType: EntityType;
	entityId: string;
	body?: string;
	pinned?: boolean;
}) {
	const { note } = await requestJson<{ note: Note }>(`/api/notes/${input.id}`, {
		method: 'PATCH',
		body: JSON.stringify({
			entity_type: input.entityType,
			entity_id: input.entityId,
			...(input.body !== undefined ? { body: input.body } : {}),
			...(input.pinned !== undefined ? { pinned: input.pinned } : {})
		})
	});
	return note;
}

export async function deleteNote(input: { id: string; entityType: EntityType; entityId: string }) {
	return requestJson<{ unlinked: boolean; note_deleted: boolean }>(`/api/notes/${input.id}`, {
		method: 'DELETE',
		body: JSON.stringify({ entity_type: input.entityType, entity_id: input.entityId })
	});
}

// --- Tags --------------------------------------------------------------------------------------------------

export type Tag = Tables<'tags'>;
export type TagAssignment = Tables<'tag_assignments'> & { tag: Tag | null };

export const tagsKey = ['collaboration', 'tags'] as const;
export const tagAssignmentsKey = (entityType: EntityType, entityId: string) =>
	['collaboration', 'tag-assignments', entityType, entityId] as const;

export async function fetchTags() {
	const { tags } = await requestJson<{ tags: Tag[] }>('/api/tags');
	return tags;
}

// Adds a tag to the organization's shared catalog without attaching it to anything. The create/edit form
// needs this because a client that has not been saved yet has nothing to assign a tag to.
export async function createTag(name: string) {
	const { tag } = await requestJson<{ tag: Tag }>('/api/tags', {
		method: 'POST',
		body: JSON.stringify({ name })
	});
	return tag;
}

export async function fetchTagAssignments(entityType: EntityType, entityId: string) {
	const { assignments } = await requestJson<{ assignments: TagAssignment[] }>(
		`/api/tags/assignments?${entityQuery(entityType, entityId)}`
	);
	return assignments;
}

// Pass tagId for an existing tag or tagName to create and apply one in the same request. The response
// carries the tag itself, so the caller can update its cache without re-fetching either list.
export async function assignTag(input: {
	tagId?: string;
	tagName?: string;
	entityType: EntityType;
	entityId: string;
}) {
	const { assignment } = await requestJson<{ assignment: TagAssignment }>('/api/tags/assignments', {
		method: 'POST',
		body: JSON.stringify({
			...(input.tagId ? { tag_id: input.tagId } : { tag_name: input.tagName }),
			entity_type: input.entityType,
			entity_id: input.entityId
		})
	});
	return assignment;
}

export async function unassignTag(assignmentId: string) {
	return requestJson<{ deleted: boolean }>(`/api/tags/assignments/${assignmentId}`, {
		method: 'DELETE'
	});
}

// --- Attachments -------------------------------------------------------------------------------------------

export type Attachment = Tables<'attachments'>;

export const attachmentsKey = (entityType: EntityType, entityId: string) =>
	['collaboration', 'attachments', entityType, entityId] as const;

export async function fetchAttachments(entityType: EntityType, entityId: string) {
	const { attachments } = await requestJson<{ attachments: Attachment[] }>(
		`/api/attachments?${entityQuery(entityType, entityId)}`
	);
	return attachments;
}

export async function presignAttachmentUpload(input: {
	entityType: EntityType;
	entityId: string;
	fileName: string;
	mimeType: string;
	sizeBytes: number;
}) {
	return requestJson<{
		upload_url: string;
		object_key: string;
		/** Both null unless the file is an image. Set when the server has reserved a slot for a preview. */
		thumbnail_upload_url: string | null;
		thumbnail_object_key: string | null;
	}>('/api/attachments/presign-upload', {
		method: 'POST',
		body: JSON.stringify({
			entity_type: input.entityType,
			entity_id: input.entityId,
			file_name: input.fileName,
			mime_type: input.mimeType,
			size_bytes: input.sizeBytes
		})
	});
}

// XHR (not fetch) so upload progress can drive a progress bar in the UI.
export function uploadAttachmentFile(
	uploadUrl: string,
	file: Blob,
	onProgress?: (fraction: number) => void
) {
	return new Promise<void>((resolve, reject) => {
		const xhr = new XMLHttpRequest();
		xhr.open('PUT', uploadUrl);
		xhr.setRequestHeader('content-type', file.type);
		xhr.upload.onprogress = (event) => {
			if (event.lengthComputable && onProgress) onProgress(event.loaded / event.total);
		};
		xhr.onload = () => {
			if (xhr.status >= 200 && xhr.status < 300) resolve();
			else reject(new Error('The file upload failed. Please try again.'));
		};
		xhr.onerror = () => reject(new Error('The file upload failed. Please try again.'));
		xhr.send(file);
	});
}

export async function createAttachment(input: {
	entityType: EntityType;
	entityId: string;
	fileName: string;
	mimeType: string;
	sizeBytes: number;
	objectKey: string;
	thumbnailObjectKey?: string | null;
}) {
	const { attachment } = await requestJson<{ attachment: Attachment }>('/api/attachments', {
		method: 'POST',
		body: JSON.stringify({
			entity_type: input.entityType,
			entity_id: input.entityId,
			file_name: input.fileName,
			mime_type: input.mimeType,
			size_bytes: input.sizeBytes,
			object_key: input.objectKey,
			...(input.thumbnailObjectKey ? { thumbnail_object_key: input.thumbnailObjectKey } : {})
		})
	});
	return attachment;
}

export async function deleteAttachment(id: string) {
	return requestJson<{ deleted: boolean }>(`/api/attachments/${id}`, { method: 'DELETE' });
}

export function isImageAttachment(attachment: Pick<Attachment, 'mime_type'>) {
	return attachment.mime_type.startsWith('image/');
}

/** Where an `<img>` points to show a photo. `thumb` is the small copy made at upload, for grids and
 *  filmstrips; the default is the original, for the big view. */
export function attachmentImageUrl(id: string, size: 'thumb' | 'full' = 'full') {
	return size === 'thumb'
		? `/api/attachments/${id}/view?size=thumb`
		: `/api/attachments/${id}/view`;
}

export async function fetchAttachmentDownloadUrl(id: string) {
	const { download_url } = await requestJson<{ download_url: string }>(
		`/api/attachments/${id}/download`
	);
	return download_url;
}

// --- Activity ----------------------------------------------------------------------------------------------

export type ActivityEvent = Tables<'activity_events'>;

export const activityKey = (entityType: EntityType, entityId: string) =>
	['collaboration', 'activity', entityType, entityId] as const;

export async function fetchActivity(entityType: EntityType, entityId: string, limit = 50) {
	const { activity_events } = await requestJson<{ activity_events: ActivityEvent[] }>(
		`/api/activity?${entityQuery(entityType, entityId)}&limit=${limit}`
	);
	return activity_events;
}

// --- Profiles ------------------------------------------------------------------------------------------------

export type Profile = { id: string; full_name: string | null; avatar_url: string | null };

export const profilesKey = (ids: string[]) =>
	['collaboration', 'profiles', [...ids].sort()] as const;

export async function fetchProfiles(ids: string[]) {
	if (ids.length === 0) return [];
	const { profiles } = await requestJson<{ profiles: Profile[] }>(
		`/api/profiles?ids=${encodeURIComponent(ids.join(','))}`
	);
	return profiles;
}
