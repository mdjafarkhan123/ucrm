import sharp from 'sharp';

// A person's profile photo. The browser crops and shrinks the picture before sending it, but nothing here
// trusts that: whatever arrives is decoded, squared, resized and re-encoded, which also drops every byte of
// metadata a phone writes into a photo — including the GPS position it was taken at.

/** The edge of the stored square. Avatars draw at 44px at most, so this stays sharp on a 3x screen. */
export const PROFILE_PHOTO_EDGE_PIXELS = 256;
const PROFILE_PHOTO_QUALITY = 82;
// Refuses a decompression bomb before libvips allocates for it: a 1 MB file claiming 50,000×50,000 pixels.
const PROFILE_PHOTO_MAX_INPUT_PIXELS = 40_000_000;

// Both shapes are also built by `set_profile_photo`, and the profiles table refuses any other.
export function profilePhotoObjectKey(userId: string, photoId: string) {
	return `profile-photos/${userId}/${photoId}.webp`;
}

export function profilePhotoUrl(userId: string, photoId: string) {
	return `/api/profile-photos/${userId}?v=${photoId}`;
}

/** Returns the stored square as WEBP, or null when the bytes are not an image the decoder accepts. */
export async function processProfilePhoto(source: Uint8Array): Promise<Uint8Array | null> {
	try {
		const photo = await sharp(source, {
			failOn: 'error',
			limitInputPixels: PROFILE_PHOTO_MAX_INPUT_PIXELS,
			// An animated GIF or WEBP keeps only its first frame.
			animated: false
		})
			// EXIF orientation, applied before the metadata goes, so a sideways phone photo stands upright.
			.rotate()
			.resize({
				width: PROFILE_PHOTO_EDGE_PIXELS,
				height: PROFILE_PHOTO_EDGE_PIXELS,
				fit: 'cover',
				position: 'centre'
			})
			.webp({ quality: PROFILE_PHOTO_QUALITY })
			.toBuffer();
		return new Uint8Array(photo);
	} catch {
		return null;
	}
}
