// How an upload is proved to be what it claims.
//
// OWASP's file upload guidance asks for three separate checks that must all agree: a business-necessary
// extension allowlist, a server-side size limit, and validation of the real file signature rather than the
// `Content-Type` the browser sent. The allowlist and the size ceiling live in `$lib/files/allowlist.ts`,
// because the file picker needs them too and one list cannot drift from itself. The signature check lives
// here, where the bytes are.
//
// This module is the answer to "is this file allowed", used by the upload route before a key is issued and
// again by the worker once the bytes exist.

import {
	ALLOWED_TYPES,
	MAX_FILE_SIZE_BYTES,
	SETUP_AUDIO_TYPES,
	allowedTypeFor,
	fileExtension,
	type AllowedType,
	type SignatureFamily
} from '$lib/files/allowlist';

export { MAX_FILE_SIZE_BYTES, fileExtension };

// How many bytes the worker must hold back from the stream to identify the file. The longest signature
// checked is WebP's 12; 64 leaves room for a format that needs a little more without buffering the object.
export const SIGNATURE_SAMPLE_BYTES = 64;

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
// which is why the worker checks the bytes again afterwards. A route with its own narrower or wider list —
// a setup question's accepted kinds — passes it as `types`.
export function checkUploadClaim(
	claim: UploadClaim,
	types: readonly AllowedType[] = ALLOWED_TYPES
): PolicyVerdict {
	const type = allowedTypeFor(claim.fileName, types);
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
	// WAV is the other RIFF container: "RIFF", four size bytes, "WAVE".
	if (
		startsWith(sample, [0x52, 0x49, 0x46, 0x46]) &&
		startsWith(sample, [0x57, 0x41, 0x56, 0x45], 8)
	)
		return 'wav';
	// M4A is an MPEG-4 file: a box size, then "ftyp".
	if (startsWith(sample, [0x66, 0x74, 0x79, 0x70], 4)) return 'm4a';
	// MP3 opens with an "ID3" tag, or straight on an MPEG audio frame: eleven set sync bits. JPEG's FF D8 has
	// only eight, and was matched above anyway.
	if (startsWith(sample, [0x49, 0x44, 0x33])) return 'mp3';
	if (sample.length >= 2 && sample[0] === 0xff && (sample[1] & 0xe0) === 0xe0) return 'mp3';
	return null;
}

// Renaming keeps the original extension, the way Explorer, Finder, Dropbox and OneDrive all do. The name is
// what a download saves as, so letting "IMG_2093.jpg" become "Boiler before" would hand the contractor a
// file their computer no longer knows how to open. It is also what `allowedTypeFor` reads, so dropping the
// extension would quietly take a live file off the allowlist.
export function renameKeepingExtension(currentName: string, requestedName: string): string {
	const extension = fileExtension(currentName);
	const typed = requestedName.trim();
	if (!extension) return typed.slice(0, 255);
	// Retyping the extension is not a mistake to correct -- it is the same name.
	if (fileExtension(typed) === extension) return typed.slice(0, 255);
	// The extension is added back afterwards, so the typed part is what gets cut if anything does.
	return `${typed.slice(0, 254 - extension.length)}.${extension}`;
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
	// Setup recordings too: only the setup route can register one, and it has already checked the question
	// asks for a recording. Here the only question is whether the bytes are what the name says.
	const type = allowedTypeFor(fileName, [...ALLOWED_TYPES, ...SETUP_AUDIO_TYPES]);
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
