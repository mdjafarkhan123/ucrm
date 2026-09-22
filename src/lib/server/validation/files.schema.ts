import { z } from 'zod';
import { attachmentEntityTypeSchema } from './collaboration.schema';
import { MAX_FILE_SIZE_BYTES } from '$lib/server/files/upload-policy';

// Where a File first entered UCRM. `file_manager` is a direct library upload with no originating record;
// every other origin names one. Mirrors the files_origin_id_matches_type_check constraint.
export const fileOriginTypeSchema = z.union([
	z.literal('file_manager'),
	attachmentEntityTypeSchema
]);

// Shape only. Whether this file type is actually allowed is `checkUploadClaim`'s answer, so the allowlist
// lives in one place instead of being half-stated here and half-stated there.
export const fileUploadStartSchema = z
	.object({
		file_name: z.string().trim().min(1).max(255),
		mime_type: z.string().trim().min(1).max(127),
		size_bytes: z.number().int().positive().max(MAX_FILE_SIZE_BYTES),
		origin_type: fileOriginTypeSchema,
		origin_id: z.uuid().nullish(),
		folder_id: z.uuid().nullish()
	})
	.refine((value) => (value.origin_type === 'file_manager') === (value.origin_id == null), {
		message: 'A file uploaded to the library has no record, and every other origin needs one.',
		path: ['origin_id']
	});

export type FileUploadStart = z.infer<typeof fileUploadStartSchema>;

// Renaming and moving one File. Both are edits to the same row and both need files.manage, so they share a
// request rather than making the panel choose between two round trips.
//
// `display_name` is only the part the contractor typed: the route puts the original extension back on
// before the name reaches the database, which is why 255 is checked there and 200 here. `folder_id` is
// nullable on purpose -- null means "take this file out of its folder" -- so absent and null are different
// answers, and the refine below is what tells them apart.
export const fileUpdateSchema = z
	.object({
		display_name: z.string().trim().min(1).max(200).optional(),
		folder_id: z.uuid().nullable().optional()
	})
	.refine((value) => value.display_name !== undefined || value.folder_id !== undefined, {
		message: 'Nothing was changed.',
		path: ['display_name']
	});

export const fileFolderCreateSchema = z.object({
	name: z.string().trim().min(1).max(120)
});

// Attaching existing Files to one record. The picker sends a whole selection, so this takes a list; the
// ceiling is the picker's own page of 40 plus room for a second page's worth, not a number the contractor
// will ever notice. Only `attachment` is offered here -- work photos and report photos are created by the
// flows that own them, with their own meaning, rather than chosen from a dropdown in a file picker.
export const fileAttachSchema = z.object({
	file_ids: z.array(z.uuid()).min(1).max(100),
	entity_type: attachmentEntityTypeSchema,
	entity_id: z.uuid()
});

// Taking one File off one record. Singular where attaching is plural, because a record's file area removes
// what the contractor pressed the button on, one decision at a time, and each one can be refused for its
// own reason.
export const fileDetachSchema = z.object({
	file_id: z.uuid(),
	entity_type: attachmentEntityTypeSchema,
	entity_id: z.uuid()
});
