import { buildSignatureObjectKey, deleteObject, putObject } from '$lib/server/storage/r2';

// A drawn signature arrives as a data URL in the request body, not through a presigned upload. The
// difference matters: presigning hands the caller a window to store any bytes they like under a key the
// database then points at. A signature has to be the bytes we looked at, so they come through here.

export const SIGNATURE_MIME_TYPE = 'image/png';

// A canvas signature at our pad's size is a few kilobytes. The ceiling is generous enough for a high
// pixel-ratio phone and far below the database column's own limit, so a refusal is always ours to
// explain rather than a raw constraint violation.
export const SIGNATURE_MAX_BYTES = 200 * 1024;

const DATA_URL_PREFIX = 'data:image/png;base64,';
const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

export type SignatureImage = { bytes: Uint8Array; byteSize: number };

// Returns null for anything that is not a real PNG of an acceptable size. The caller turns that into one
// sentence; nothing here explains which of the checks failed, because the only people who would learn
// something from that detail are the ones trying to get past it.
export function decodeSignatureImage(dataUrl: string): SignatureImage | null {
	if (!dataUrl.startsWith(DATA_URL_PREFIX)) return null;

	const encoded = dataUrl.slice(DATA_URL_PREFIX.length);
	// Base64 carries about a third more than the file it holds, so the cheap length check comes first and
	// an oversized body never reaches the decoder.
	if (encoded.length === 0 || encoded.length > Math.ceil((SIGNATURE_MAX_BYTES * 4) / 3) + 4) {
		return null;
	}

	let bytes: Uint8Array;
	try {
		bytes = Uint8Array.from(Buffer.from(encoded, 'base64'));
	} catch {
		return null;
	}

	if (bytes.byteLength === 0 || bytes.byteLength > SIGNATURE_MAX_BYTES) return null;
	// The declared type is the caller's claim; the first eight bytes are the file's own answer.
	if (bytes.byteLength < PNG_MAGIC.length) return null;
	if (PNG_MAGIC.some((byte, index) => bytes[index] !== byte)) return null;

	return { bytes, byteSize: bytes.byteLength };
}

// Stored before the command runs and outside every lock, because the behavior contract forbids a network
// call while a row is held. If the command then refuses, the object is unreferenced and swept up by
// `discardSignatureImage` - an orphan nobody can name is cheaper than a lock held across the wire.
export async function storeSignatureImage(
	organizationId: string,
	quoteId: string,
	image: SignatureImage
): Promise<string> {
	const objectKey = buildSignatureObjectKey(organizationId, quoteId);
	await putObject(objectKey, image.bytes, SIGNATURE_MIME_TYPE);
	return objectKey;
}

// Best effort on purpose. A failed cleanup must never turn a recorded approval into an error the customer
// sees, and must never be the reason a refusal is reported as something else.
export async function discardSignatureImage(objectKey: string | null | undefined): Promise<void> {
	if (!objectKey) return;
	try {
		await deleteObject(objectKey);
	} catch {
		// Nothing points at it, so nothing is broken by it staying.
	}
}
