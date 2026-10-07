import { z } from 'zod';

// The browser sends an already-cropped square of a few dozen kilobytes. The ceiling leaves room for a
// browser that cannot crop and sends the picture as chosen, without letting a full camera original through
// to the decoder. SVG is absent for the same reason as the logo: it is a document that can carry script.
export const PROFILE_PHOTO_MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp'] as const;
export const PROFILE_PHOTO_MAX_BYTES = 2 * 1024 * 1024;

export const userIdParamSchema = z.uuid();

export const profilePhotoUploadSchema = z.object({
	photo: z
		.instanceof(File, { message: 'Choose a photo to upload.' })
		.refine((file) => file.size > 0, 'That photo is empty.')
		.refine(
			(file) => (PROFILE_PHOTO_MIME_TYPES as readonly string[]).includes(file.type),
			'Upload a JPG, PNG, or WEBP photo.'
		)
		.refine((file) => file.size <= PROFILE_PHOTO_MAX_BYTES, 'That photo is too large.')
});
