import { z } from 'zod';

// Shared by notes, tags, tag assignments, and attachments. Jobs and Invoices extend this list when they
// become linkable, matching the migration's entity_type check constraints.
export const linkedEntityTypeSchema = z.enum(['client', 'property', 'request', 'quote']);

export const MAX_ATTACHMENT_SIZE_BYTES = 26_214_400; // 25 MB, matches the attachments table check constraint
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

export const noteCreateSchema = z.object({
	entity_type: linkedEntityTypeSchema,
	entity_id: z.string().uuid('Choose a record to attach this note to.'),
	body: z.string().trim().min(1, 'Write a note before saving.').max(4000),
	pinned: z.boolean().default(false)
});

// entity_type/entity_id identify which linked view the caller is acting from, since permission for a
// manage action on a note depends on the entity it's linked to, not the note itself.
export const noteUpdateRequestSchema = z
	.object({
		entity_type: linkedEntityTypeSchema,
		entity_id: z.string().uuid(),
		body: z.string().trim().min(1, 'Write a note before saving.').max(4000).optional(),
		pinned: z.boolean().optional()
	})
	.refine((value) => value.body !== undefined || value.pinned !== undefined, {
		message: 'Nothing to update.'
	});

// Unlinking a note from one scope; the route deletes the note itself once its last link is removed.
export const noteUnlinkRequestSchema = z.object({
	entity_type: linkedEntityTypeSchema,
	entity_id: z.string().uuid()
});

export const tagCreateSchema = z.object({
	name: z.string().trim().min(1, 'Enter a tag name.').max(40),
	color: z
		.string()
		.trim()
		.regex(/^#[0-9a-fA-F]{6}$/, 'Enter a valid hex color.')
		.optional()
});

// Either applies an existing tag (tag_id) or creates and applies one in the same request (tag_name), so
// picking a brand-new tag costs one round trip instead of a create call followed by an assign call.
export const tagAssignmentCreateSchema = z
	.object({
		tag_id: z.string().uuid('Choose a tag.').optional(),
		tag_name: z.string().trim().min(1, 'Enter a tag name.').max(40).optional(),
		entity_type: linkedEntityTypeSchema,
		entity_id: z.string().uuid('Choose a record to tag.')
	})
	.refine((value) => Boolean(value.tag_id) !== Boolean(value.tag_name), {
		message: 'Choose an existing tag or enter a new tag name.',
		path: ['tag_id']
	});

export const attachmentPresignSchema = z.object({
	entity_type: linkedEntityTypeSchema,
	entity_id: z.string().uuid('Choose a record to attach a file to.'),
	file_name: z.string().trim().min(1, 'Choose a file.').max(255),
	mime_type: z.enum(ALLOWED_ATTACHMENT_MIME_TYPES, {
		message: 'That file type is not supported.'
	}),
	size_bytes: z
		.number()
		.int()
		.positive()
		.max(MAX_ATTACHMENT_SIZE_BYTES, 'Files must be 25 MB or smaller.')
});

export const attachmentCreateSchema = attachmentPresignSchema.extend({
	object_key: z.string().trim().min(1),
	// Set only when the browser managed to make a small preview of a photo. The route checks it sits under
	// the same org/entity prefix as the original before storing it.
	thumbnail_object_key: z.string().trim().min(1).optional(),
	note_id: z.string().uuid().optional()
});

export const propertyContactSchema = z
	.object({
		first_name: z.string().trim().max(80).optional().or(z.literal('')),
		last_name: z.string().trim().max(80).optional().or(z.literal('')),
		role_label: z.string().trim().max(80).optional().or(z.literal('')),
		is_primary: z.boolean().default(false)
	})
	.refine((value) => Boolean(value.first_name?.trim()) || Boolean(value.last_name?.trim()), {
		message: 'Enter a first or last name.',
		path: ['first_name']
	});

export function validContactMethodValue(kind: 'email' | 'phone', value: string): boolean {
	return kind === 'email'
		? z.string().email().safeParse(value).success
		: value.replace(/[^0-9]/g, '').length >= 7;
}

export const propertyContactMethodSchema = z
	.object({
		property_contact_id: z.string().uuid().optional(),
		kind: z.enum(['email', 'phone']),
		value: z.string().trim().min(3).max(254),
		label: z.string().trim().max(40).optional().or(z.literal('')),
		is_primary: z.boolean().default(false)
	})
	.refine((value) => validContactMethodValue(value.kind, value.value), {
		message: 'Enter a valid email or phone number.',
		path: ['value']
	});

export const propertyContactUpdateSchema = z
	.object({
		first_name: z.string().trim().max(80).optional().or(z.literal('')),
		last_name: z.string().trim().max(80).optional().or(z.literal('')),
		role_label: z.string().trim().max(80).optional().or(z.literal('')),
		is_primary: z.boolean().optional()
	})
	.refine((value) => Object.keys(value).length > 0, { message: 'Nothing to update.' });

// Notes, tags, attachments, and activity all record a user id (created_by, edited_by, uploaded_by,
// actor_user_id). The UI resolves those ids to names/avatars through this one batch lookup rather than
// each API route joining `profiles` itself.
export const profileIdsQuerySchema = z.object({
	ids: z.array(z.string().uuid()).min(1).max(100, 'Request 100 or fewer profiles at a time.')
});

export const propertyContactMethodUpdateSchema = z
	.object({
		value: z.string().trim().min(3).max(254).optional(),
		label: z.string().trim().max(40).optional().or(z.literal('')),
		is_primary: z.boolean().optional()
	})
	.refine((value) => Object.keys(value).length > 0, { message: 'Nothing to update.' });
