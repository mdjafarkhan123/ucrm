// Client-safe mirror of the same constants in `$lib/server/validation/collaboration.schema.ts` (that file
// is server-only and can't be imported from browser code). Keep both lists in sync.
export const MAX_ATTACHMENT_SIZE_BYTES = 26_214_400; // 25 MB

export const ALLOWED_ATTACHMENT_MIME_TYPES = [
	'image/jpeg',
	'image/png',
	'image/gif',
	'image/webp',
	'image/heic',
	'application/pdf',
	'text/plain',
	'text/csv',
	'application/msword',
	'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
	'application/vnd.ms-excel',
	'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
	'application/zip'
] as const;

export function isAllowedAttachmentType(mimeType: string): boolean {
	return (ALLOWED_ATTACHMENT_MIME_TYPES as readonly string[]).includes(mimeType);
}
