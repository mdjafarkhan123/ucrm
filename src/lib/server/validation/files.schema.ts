import { z } from 'zod';
import { attachmentEntityTypeSchema } from './collaboration.schema';
import { MAX_FILE_SIZE_BYTES } from '$lib/server/files/upload-policy';

// Every entity the Files catalog can link a File to. Invoice and organization never had the legacy
// attachments pipeline `attachmentEntityTypeSchema` guards, so that schema keeps matching the attachments
// table's own check constraint and this one matches files_origin_type_check / file_links_entity_type_check
// instead, which Part 6A widened to include 'invoice', Part 6D widened to include 'organization', and Part
// 6F widened to include 'marketing_campaign', and deferred sweep 7e to include 'catalog_item'.
export const fileEntityTypeSchema = z.enum([
	...attachmentEntityTypeSchema.options,
	'invoice',
	'organization',
	'marketing_campaign',
	'catalog_item'
]);

// Where a File first entered UCRM. `file_manager` is a direct library upload with no originating record;
// every other origin names one. Mirrors the files_origin_id_matches_type_check constraint.
export const fileOriginTypeSchema = z.union([z.literal('file_manager'), fileEntityTypeSchema]);

// Mirrors files_origin_role_check: the file_links role the processing worker will link the upload with,
// once it is available. Only a line photo or a business logo is chosen by the caller today -- every other
// upload is a plain 'attachment', so the field defaults to it and most callers never send it at all.
export const fileOriginRoleSchema = z.enum([
	'attachment',
	'line_photo',
	'logo',
	'campaign_image',
	'item_photo'
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
		folder_id: z.uuid().nullish(),
		origin_role: fileOriginRoleSchema.default('attachment')
	})
	.refine((value) => (value.origin_type === 'file_manager') === (value.origin_id == null), {
		message: 'A file uploaded to the library has no record, and every other origin needs one.',
		path: ['origin_id']
	})
	.refine((value) => value.origin_role === 'attachment' || value.origin_id != null, {
		message: 'A line photo needs the record it was picked on.',
		path: ['origin_role']
	});

export type FileUploadStart = z.infer<typeof fileUploadStartSchema>;

// Renaming and moving one File. Both are edits to the same row and both need files.manage, so they share a
// request rather than making the panel choose between two round trips.
//
// `display_name` is only the part the contractor typed: the route puts the original extension back on
// before the name reaches the database, which is why 255 is checked there and 200 here. `folder_id` is
// nullable on purpose -- null means "take this file out of its folder" -- so absent and null are different
// answers, and the refine below is what tells them apart.
//
// `caption` and `label_ids` are the Part 7B description of a photo. They ride the same request but a looser
// permission -- anyone who may add photos to a job the photo is on may describe it -- so the route checks
// them apart from the name and folder. An empty caption clears it; an empty label list removes every label.
export const fileUpdateSchema = z
	.object({
		display_name: z.string().trim().min(1).max(200).optional(),
		folder_id: z.uuid().nullable().optional(),
		caption: z.string().trim().max(500).nullable().optional(),
		label_ids: z.array(z.uuid()).max(100).optional()
	})
	.refine(
		(value) =>
			value.display_name !== undefined ||
			value.folder_id !== undefined ||
			value.caption !== undefined ||
			value.label_ids !== undefined,
		{ message: 'Nothing was changed.', path: ['display_name'] }
	);

// One photo label. Mirrors file_labels_name_check.
export const fileLabelSchema = z.object({
	name: z.string().trim().min(1).max(40)
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
	entity_type: fileEntityTypeSchema,
	entity_id: z.uuid()
});

// Taking one File off one record. Singular where attaching is plural, because a record's file area removes
// what the contractor pressed the button on, one decision at a time, and each one can be refused for its
// own reason.
export const fileDetachSchema = z.object({
	file_id: z.uuid(),
	entity_type: fileEntityTypeSchema,
	entity_id: z.uuid()
});

// Moving a File to Trash. The hardest warning level -- a customer already received it on a published
// quote -- needs this explicit tick before the database will let it go (trash_file's P0412 otherwise).
export const fileTrashSchema = z.object({
	acknowledge_customer_copies: z.boolean().optional().default(false)
});

// Making one customer file share (Part 7D). The limits are the behavior contract's: one Client, at most 50
// Files, and a choice of three lengths rather than a date, so a link can never be made to last for ever.
export const fileShareCreateSchema = z.object({
	client_id: z.uuid(),
	file_ids: z
		.array(z.uuid())
		.min(1, 'Choose at least one file to share.')
		.max(50, 'A share holds at most 50 files.')
		.refine((ids) => new Set(ids).size === ids.length, 'The same file was chosen twice.'),
	days: z.union([z.literal(7), z.literal(30), z.literal(90)])
});

// Turning one customer file share off. The share is named by the URL; there is nothing else to choose.
export const fileShareTurnOffSchema = z.object({ id: z.uuid() });
