// What the File Manager accepts, and how an upload is proved to be what it claims.
//
// OWASP's file upload guidance asks for three separate checks that must all agree: a business-necessary
// extension allowlist, a server-side size limit, and validation of the real file signature rather than the
// `Content-Type` the browser sent. All three live here so there is one answer to "is this file allowed",
// used by the upload route before a key is issued and again by the worker once the bytes exist.
//
// Video is deliberately absent. The behavior contract requires video's first formats, duration and byte
// limits to come from measured mobile upload, processing, playback and storage evidence rather than a
// competitor's number, and that evidence does not exist yet.

// Jafar approved 100 MB on 2026-09-21, matching Jobber's and CompanyCam's documented per-file limits.
export const MAX_FILE_SIZE_BYTES = 104_857_600;

type SignatureFamily = 'jpeg' | 'png' | 'gif' | 'webp' | 'pdf' | 'zip' | 'ole' | 'none';

type AllowedType = {
	extensions: readonly string[];
	mimeTypes: readonly string[];
	signature: SignatureFamily;
};

// Kept narrow on purpose: the formats a contractor actually sends a customer or keeps as job evidence.
// Anything a browser or Office viewer could be talked into executing stays out.
const ALLOWED_TYPES: readonly AllowedType[] = [
	{ extensions: ['jpg', 'jpeg'], mimeTypes: ['image/jpeg'], signature: 'jpeg' },
	{ extensions: ['png'], mimeTypes: ['image/png'], signature: 'png' },
	{ extensions: ['gif'], mimeTypes: ['image/gif'], signature: 'gif' },
	{ extensions: ['webp'], mimeTypes: ['image/webp'], signature: 'webp' },
	{ extensions: ['pdf'], mimeTypes: ['application/pdf'], signature: 'pdf' },
	{
		extensions: ['docx'],
		mimeTypes: ['application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
		signature: 'zip'
	},
	{
		extensions: ['xlsx'],
		mimeTypes: ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
		signature: 'zip'
	},
	{ extensions: ['doc'], mimeTypes: ['application/msword'], signature: 'ole' },
	{ extensions: ['xls'], mimeTypes: ['application/vnd.ms-excel'], signature: 'ole' },
	// Plain text has no signature to check. Both are inert: nothing renders or executes them, they are
	// downloaded or parsed as data, so the extension and size checks carry the weight alone.
	{ extensions: ['csv'], mimeTypes: ['text/csv'], signature: 'none' },
	{ extensions: ['txt'], mimeTypes: ['text/plain'], signature: 'none' }
];

// How many bytes the worker must hold back from the stream to identify the file. The longest signature
// checked is WebP's 12; 64 leaves room for a format that needs a little more without buffering the object.
export const SIGNATURE_SAMPLE_BYTES = 64;

export function fileExtension(fileName: string): string {
	const dot = fileName.lastIndexOf('.');
	if (dot <= 0 || dot === fileName.length - 1) return '';
	return fileName.slice(dot + 1).toLowerCase();
}

function allowedTypeFor(fileName: string): AllowedType | null {
	const extension = fileExtension(fileName);
	if (!extension) return null;
	return ALLOWED_TYPES.find((type) => type.extensions.includes(extension)) ?? null;
}

export type UploadClaim = {
	fileName: string;
	mimeType: string;
	sizeBytes: number;
};

export type PolicyRefusal = {
	allowed: false;
	field: 'file_name' | 'mime_type' | 'size_bytes';
	reason: string;
};

export type PolicyVerdict = { allowed: true; signature: SignatureFamily } | PolicyRefusal;

// The check the upload route runs before any storage key is issued. It sees only what the browser claims,
// which is why the worker checks the bytes again afterwards.
export function checkUploadClaim(claim: UploadClaim): PolicyVerdict {
	const type = allowedTypeFor(claim.fileName);
	if (!type)
		return {
			allowed: false,
			field: 'file_name',
			reason: 'That kind of file cannot be added to the file library.'
		};

	if (!type.mimeTypes.includes(claim.mimeType.toLowerCase()))
		return {
			allowed: false,
			field: 'mime_type',
			reason: 'That file type does not match the file name.'
		};

	if (!Number.isInteger(claim.sizeBytes) || claim.sizeBytes <= 0)
		return { allowed: false, field: 'size_bytes', reason: 'That file is empty.' };

	if (claim.sizeBytes > MAX_FILE_SIZE_BYTES)
		return { allowed: false, field: 'size_bytes', reason: 'Files can be up to 100 MB.' };

	return { allowed: true, signature: type.signature };
}

function startsWith(sample: Uint8Array, bytes: readonly number[], offset = 0): boolean {
	if (sample.length < offset + bytes.length) return false;
	return bytes.every((byte, index) => sample[offset + index] === byte);
}

// Reads the leading bytes and says which family they really are. Unknown content answers null, which the
// worker treats as a refusal rather than a pass -- an allowlist fails closed.
export function detectSignature(sample: Uint8Array): SignatureFamily | null {
	if (startsWith(sample, [0xff, 0xd8, 0xff])) return 'jpeg';
	if (startsWith(sample, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
	// GIF87a and GIF89a share the first four bytes.
	if (startsWith(sample, [0x47, 0x49, 0x46, 0x38])) return 'gif';
	// WebP is a RIFF container: "RIFF" then four size bytes then "WEBP".
	if (
		startsWith(sample, [0x52, 0x49, 0x46, 0x46]) &&
		startsWith(sample, [0x57, 0x45, 0x42, 0x50], 8)
	)
		return 'webp';
	if (startsWith(sample, [0x25, 0x50, 0x44, 0x46])) return 'pdf';
	// Every modern Office file is a zip. "PK\x03\x04" is a populated archive; the empty-archive variants
	// are not accepted, since a real .docx always has entries.
	if (startsWith(sample, [0x50, 0x4b, 0x03, 0x04])) return 'zip';
	// The pre-2007 Office compound-document header.
	if (startsWith(sample, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) return 'ole';
	return null;
}

export type ContentVerdict = { ok: true } | { ok: false; reason: string };

// The check the worker runs against the bytes that actually landed. `expected` comes from the extension
// the File was registered under, so this is asking one question: does the content match what we were told?
export function checkUploadedContent(
	fileName: string,
	sample: Uint8Array,
	actualSizeBytes: number,
	registeredSizeBytes: number
): ContentVerdict {
	const type = allowedTypeFor(fileName);
	if (!type) return { ok: false, reason: 'That kind of file cannot be added to the file library.' };

	if (actualSizeBytes > MAX_FILE_SIZE_BYTES)
		return { ok: false, reason: 'Files can be up to 100 MB.' };

	if (actualSizeBytes <= 0) return { ok: false, reason: 'That file is empty.' };

	// The browser told us a size before uploading and R2 reports what it stored. A mismatch means the
	// object is not the file that was approved, so it is refused rather than checked further.
	if (actualSizeBytes !== registeredSizeBytes)
		return {
			ok: false,
			reason: 'This file changed while it was uploading. Please upload it again.'
		};

	if (type.signature === 'none') return { ok: true };

	if (detectSignature(sample) !== type.signature)
		return { ok: false, reason: 'The inside of this file does not match its file name.' };

	return { ok: true };
}
