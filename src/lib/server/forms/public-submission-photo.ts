import { putObject } from '$lib/server/storage/r2';

// A photo attached to a public form arrives as a data URL in the request body, not through a presigned
// upload -- the same reasoning as `signature-image.ts`: presigning hands an anonymous stranger a window to
// store whatever bytes they like at a key we then trust. A public form is the one upload surface with no
// login at all behind it, so this is the one place that reasoning matters most.

export const PUBLIC_FORM_PHOTO_MAX_BYTES = 8 * 1024 * 1024; // 8MB per photo
export const PUBLIC_FORM_PHOTO_TOTAL_MAX_BYTES = 25 * 1024 * 1024; // 25MB per submission
export const PUBLIC_FORM_PHOTO_MAX_COUNT = 20; // matches submit_form_response's own max_photos

const DATA_URL_PATTERN = /^data:image\/(png|jpe?g|webp);base64,/i;
const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG_MAGIC = [0xff, 0xd8, 0xff];

// WebP is a RIFF container -- the format tag that actually says "WEBP" sits at byte 8, not byte 0.
function isWebp(bytes: Uint8Array): boolean {
	if (bytes.byteLength < 12) return false;
	return (
		bytes[0] === 0x52 &&
		bytes[1] === 0x49 &&
		bytes[2] === 0x46 &&
		bytes[3] === 0x46 &&
		bytes[8] === 0x57 &&
		bytes[9] === 0x45 &&
		bytes[10] === 0x42 &&
		bytes[11] === 0x50
	);
}

// The declared type on the data URL is the caller's claim; the file's own first bytes are its answer. Only
// these three formats are accepted, matching what every browser can capture from a camera or file picker.
function detectMimeType(bytes: Uint8Array): string | null {
	if (bytes.byteLength >= PNG_MAGIC.length && PNG_MAGIC.every((byte, i) => bytes[i] === byte)) {
		return 'image/png';
	}
	if (bytes.byteLength >= JPEG_MAGIC.length && JPEG_MAGIC.every((byte, i) => bytes[i] === byte)) {
		return 'image/jpeg';
	}
	if (isWebp(bytes)) return 'image/webp';
	return null;
}

export type DecodedPublicFormPhoto = { bytes: Uint8Array; byteSize: number; mimeType: string };

// Returns null for anything that is not a real PNG/JPEG/WebP of an acceptable size. The caller turns that
// into one plain sentence; nothing here explains which check failed, because the only person who learns
// something from that detail is someone trying to get past it.
export function decodePublicFormPhoto(dataUrl: string): DecodedPublicFormPhoto | null {
	const match = DATA_URL_PATTERN.exec(dataUrl);
	if (!match) return null;

	const encoded = dataUrl.slice(match[0].length);
	// Base64 carries about a third more than the file it holds, so the cheap length check comes first and
	// an oversized body never reaches the decoder.
	if (
		encoded.length === 0 ||
		encoded.length > Math.ceil((PUBLIC_FORM_PHOTO_MAX_BYTES * 4) / 3) + 4
	) {
		return null;
	}

	let bytes: Uint8Array;
	try {
		bytes = Uint8Array.from(Buffer.from(encoded, 'base64'));
	} catch {
		return null;
	}

	if (bytes.byteLength === 0 || bytes.byteLength > PUBLIC_FORM_PHOTO_MAX_BYTES) return null;

	const mimeType = detectMimeType(bytes);
	if (!mimeType) return null;

	return { bytes, byteSize: bytes.byteLength, mimeType };
}

export async function storePublicFormPhotoAt(
	objectKey: string,
	photo: DecodedPublicFormPhoto
): Promise<string> {
	await putObject(objectKey, photo.bytes, photo.mimeType);
	return objectKey;
}
