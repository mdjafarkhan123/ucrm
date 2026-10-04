// What the File Manager accepts, in the one place both sides read it.
//
// `$lib/server/files/upload-policy.ts` imports this list and adds the checks that only make sense on the
// server: the real file signature, and what the bytes turned out to be. The browser reads it to fill the
// picker's `accept` attribute and to say "that kind of file cannot be added" before a 100 MB upload starts
// rather than after. Neither side is the authority on its own — the server refuses anything this list does
// not cover, and the browser is only being quick about it.
//
// Kept narrow on purpose: the formats a contractor actually sends a customer or keeps as job evidence.
// Anything a browser or Office viewer could be talked into executing stays out. Video and HEIC are
// deliberately absent; `docs/files-media-behavior-contract.md` records why, and Jafar settled both.

/** Jafar approved 100 MB on 2026-09-21, matching Jobber's and CompanyCam's documented per-file limits. */
export const MAX_FILE_SIZE_BYTES = 104_857_600;

export type SignatureFamily =
	'jpeg' | 'png' | 'gif' | 'webp' | 'pdf' | 'zip' | 'ole' | 'mp3' | 'm4a' | 'wav' | 'none';

export type AllowedType = {
	extensions: readonly string[];
	mimeTypes: readonly string[];
	signature: SignatureFamily;
};

export const ALLOWED_TYPES: readonly AllowedType[] = [
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

/**
 * Voice recordings — a voicemail greeting, say — accepted only as an answer to a setup question that asks for
 * one (client onboarding A5c; Jafar, 2026-10-04). The File library itself still refuses audio. The first MIME
 * type is the one stored; the rest are what browsers on different systems report for the same file.
 */
export const SETUP_AUDIO_TYPES: readonly AllowedType[] = [
	{ extensions: ['mp3'], mimeTypes: ['audio/mpeg', 'audio/mp3'], signature: 'mp3' },
	{ extensions: ['m4a'], mimeTypes: ['audio/mp4', 'audio/x-m4a', 'audio/m4a'], signature: 'm4a' },
	{
		extensions: ['wav'],
		mimeTypes: ['audio/wav', 'audio/x-wav', 'audio/wave', 'audio/vnd.wave'],
		signature: 'wav'
	}
];

export function fileExtension(fileName: string): string {
	const dot = fileName.lastIndexOf('.');
	if (dot <= 0 || dot === fileName.length - 1) return '';
	return fileName.slice(dot + 1).toLowerCase();
}

/** The entry of `types` — the File library's list unless a caller narrows or widens it — that a name belongs to. */
export function allowedTypeFor(
	fileName: string,
	types: readonly AllowedType[] = ALLOWED_TYPES
): AllowedType | null {
	const extension = fileExtension(fileName);
	if (!extension) return null;
	return types.find((type) => type.extensions.includes(extension)) ?? null;
}

/** A picker's `accept` filter for `types`. */
export function pickerAccept(types: readonly AllowedType[]): string {
	return [
		...types.flatMap((type) => type.extensions.map((extension) => `.${extension}`)),
		...types.flatMap((type) => type.mimeTypes)
	].join(',');
}

// The file picker's filter. Extensions as well as MIME types, because a browser that does not recognise a
// type still matches the extension, and one that matches neither would grey out a file the app accepts.
export const FILE_PICKER_ACCEPT = pickerAccept(ALLOWED_TYPES);
