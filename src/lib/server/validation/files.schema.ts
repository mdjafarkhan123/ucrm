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
