// Makes the small copy of a photo that the attachments grid and the lightbox filmstrip draw.
//
// It happens here, in the browser, at the moment the office picks the file. A phone photo is several
// megabytes; a page showing ten of them as small squares would pull down tens of megabytes to paint a strip
// of thumbnails, which is exactly the situation someone standing on a job site with one bar cannot afford.
// Shrinking first costs a few milliseconds once and is then free forever.

/** Longest edge of the small copy, in pixels. Big enough to stay sharp on a retina screen at the sizes the
 *  grid and filmstrip actually draw, small enough that a dozen of them cost less than one original. */
const MAX_EDGE_PIXELS = 480;

/** JPEG rather than the original format: it is the smallest of the formats every browser can write, and a
 *  preview has no need for transparency or an animated frame. */
const THUMBNAIL_MIME_TYPE = 'image/jpeg';
const THUMBNAIL_QUALITY = 0.8;

/**
 * Returns a downscaled JPEG of an image file, or null when one cannot be made — the file is not an image,
 * the browser cannot decode the format (HEIC straight off an iPhone is the common one), or the canvas is
 * unavailable. Callers treat null as "no preview" and fall back to the original, so this never throws and
 * never blocks an upload.
 */
export async function createImageThumbnail(file: File): Promise<Blob | null> {
	if (!file.type.startsWith('image/')) return null;
	if (typeof createImageBitmap !== 'function') return null;

	let bitmap: ImageBitmap;
	try {
		bitmap = await createImageBitmap(file);
	} catch {
		return null;
	}

	try {
		const scale = Math.min(1, MAX_EDGE_PIXELS / Math.max(bitmap.width, bitmap.height));
		const width = Math.max(1, Math.round(bitmap.width * scale));
		const height = Math.max(1, Math.round(bitmap.height * scale));

		const canvas = document.createElement('canvas');
		canvas.width = width;
		canvas.height = height;

		const context = canvas.getContext('2d');
		if (!context) return null;
		context.drawImage(bitmap, 0, 0, width, height);

		return await new Promise<Blob | null>((resolve) => {
			canvas.toBlob((blob) => resolve(blob), THUMBNAIL_MIME_TYPE, THUMBNAIL_QUALITY);
		});
	} catch {
		return null;
	} finally {
		bitmap.close();
	}
}
