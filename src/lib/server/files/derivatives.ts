// The safe preview a list, grid or filmstrip draws instead of the original.
//
// Contractors upload phone photos: three to twelve megabytes each. A File Manager page showing fifty of
// them as small squares would pull down half a gigabyte to paint a strip of thumbnails, which is exactly
// what someone standing on a job site with one bar cannot afford. One 480px JPEG per photo costs a few
// tens of kilobytes and is then cached forever.
//
// This runs in the processing worker, after the signature check and the malware scan have both passed, so
// libvips is never handed bytes nothing has looked at. The attachments path still makes its thumbnail in
// the browser; that stays as it is until Part 5 moves those flows onto the catalog.

import sharp from 'sharp';
import { fileExtension } from './upload-policy';

// Longest edge of the preview. Matches the browser-side thumbnail the attachments grid already uses, so
// both paths draw at the same sharpness on a retina screen.
export const THUMBNAIL_MAX_EDGE_PIXELS = 480;
const THUMBNAIL_QUALITY = 80;

// A thumbnail needs the whole encoded image in memory at once -- libvips decodes from a buffer, and no
// streaming decoder exists for the formats we accept. The worker handles one file at a time, so this cap
// is also the worker's peak memory for derivatives. Forty megabytes covers every phone and mirrorless
// camera photo; a larger image is still published, just without a generated preview.
export const THUMBNAIL_SOURCE_MAX_BYTES = 41_943_040;

// Only raster images from the allowlist. PDFs and Office documents get a typed icon: rendering a PDF page
// needs a second, much heavier toolchain, and a document icon is what Jobber and Drive show in a list
// anyway.
const PREVIEWABLE_EXTENSIONS: readonly string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp'];

/** Whether this upload is worth holding in memory during the verification pass. */
export function wantsThumbnail(fileName: string, sizeBytes: number): boolean {
	if (sizeBytes <= 0 || sizeBytes > THUMBNAIL_SOURCE_MAX_BYTES) return false;
	return PREVIEWABLE_EXTENSIONS.includes(fileExtension(fileName));
}

/**
 * Returns a downscaled JPEG of an image, or null when one cannot be made. Never throws: a file the decoder
 * refuses is still a perfectly good file to keep and download, so a failed preview must never cost an
 * upload its availability.
 */
export async function createThumbnail(source: Uint8Array): Promise<Uint8Array | null> {
	try {
		const thumbnail = await sharp(source, { failOn: 'error' })
			// EXIF orientation, so a photo taken sideways is not previewed sideways.
			.rotate()
			.resize({
				width: THUMBNAIL_MAX_EDGE_PIXELS,
				height: THUMBNAIL_MAX_EDGE_PIXELS,
				fit: 'inside',
				withoutEnlargement: true
			})
			// JPEG has no transparency, and an unflattened PNG would come out with black where it was clear.
			.flatten({ background: '#ffffff' })
			.jpeg({ quality: THUMBNAIL_QUALITY, mozjpeg: true })
			.toBuffer();

		return new Uint8Array(thumbnail);
	} catch (error) {
		console.warn('Could not make a preview for an uploaded image.', {
			error: error instanceof Error ? error.message : error
		});
		return null;
	}
}
