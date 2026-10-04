// Client onboarding A5c: a setup question answered with photos or files (plan §2.1). Jafar picks which kinds
// a question accepts and how many files it takes, the way a Google Forms file question does. The files are
// ordinary File Manager Files (ADR 0002); the answer is the list of their ids.

import {
	ALLOWED_TYPES,
	SETUP_AUDIO_TYPES,
	allowedTypeFor,
	pickerAccept,
	type AllowedType
} from '$lib/files/allowlist';

export const SETUP_FILE_KINDS = ['photo', 'document', 'audio'] as const;
export type SetupFileKind = (typeof SETUP_FILE_KINDS)[number];

/** How many files a question may take. Mirrors setup_items_max_files_check. */
export const SETUP_MAX_FILES_CHOICES = [1, 5, 10, 20] as const;

export const SETUP_FILE_KIND_LABELS: Record<SetupFileKind, { label: string; formats: string }> = {
	photo: { label: 'Photos', formats: 'JPG, PNG, WEBP, GIF' },
	document: { label: 'Documents', formats: 'PDF, Word, Excel, CSV, TXT' },
	audio: { label: 'Voice recordings', formats: 'MP3, M4A, WAV' }
};

const PHOTO_SIGNATURES = new Set(['jpeg', 'png', 'gif', 'webp']);

const TYPES: Record<SetupFileKind, readonly AllowedType[]> = {
	photo: ALLOWED_TYPES.filter((type) => PHOTO_SIGNATURES.has(type.signature)),
	document: ALLOWED_TYPES.filter((type) => !PHOTO_SIGNATURES.has(type.signature)),
	audio: SETUP_AUDIO_TYPES
};

/** Every file type a question accepting `kinds` takes. */
export function setupFileTypes(kinds: readonly SetupFileKind[]): AllowedType[] {
	return SETUP_FILE_KINDS.filter((kind) => kinds.includes(kind)).flatMap((kind) => TYPES[kind]);
}

/** The file type `fileName` is, when a question accepting `kinds` takes it. */
export function setupFileType(fileName: string, kinds: readonly SetupFileKind[]) {
	return allowedTypeFor(fileName, setupFileTypes(kinds));
}

export function setupFileAccept(kinds: readonly SetupFileKind[]) {
	return pickerAccept(setupFileTypes(kinds));
}

/** "photos or documents", for sentences like "Add photos or documents". */
export function setupFileKindsPhrase(kinds: readonly SetupFileKind[]) {
	const words = SETUP_FILE_KINDS.filter((kind) => kinds.includes(kind)).map((kind) =>
		SETUP_FILE_KIND_LABELS[kind].label.toLowerCase()
	);
	if (words.length <= 1) return words[0] ?? 'files';
	return `${words.slice(0, -1).join(', ')} or ${words[words.length - 1]}`;
}

/** The formats a question accepting `kinds` takes, for its help line: "JPG, PNG, WEBP, GIF, PDF, …". */
export function setupFileFormats(kinds: readonly SetupFileKind[]) {
	return SETUP_FILE_KINDS.filter((kind) => kinds.includes(kind))
		.map((kind) => SETUP_FILE_KIND_LABELS[kind].formats)
		.join(', ');
}

const FILE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A photo or file answer: the ids of the files it holds, in the order the client added them. */
export function parseSetupFileIds(
	raw: string,
	maxFiles: number
): { value: string[]; error: null } | { value: null; error: string } {
	let list: unknown;
	try {
		list = JSON.parse(raw);
	} catch {
		list = undefined;
	}
	if (!Array.isArray(list) || list.length === 0 || list.some((id) => typeof id !== 'string'))
		return { value: null, error: 'Add a file.' };
	const ids = (list as string[]).map((id) => id.toLowerCase());
	if (ids.some((id) => !FILE_ID.test(id))) return { value: null, error: 'Add a file.' };
	if (new Set(ids).size !== ids.length) return { value: null, error: 'A file is added twice.' };
	if (ids.length > maxFiles)
		return {
			value: null,
			error: maxFiles === 1 ? 'Add one file only.' : `Add up to ${maxFiles} files.`
		};
	return { value: ids, error: null };
}

/** The ids a stored answer's text holds, or an empty list when it holds none. */
export function setupFileIds(raw: string | null | undefined): string[] {
	if (!raw?.startsWith('[')) return [];
	try {
		const list: unknown = JSON.parse(raw);
		return Array.isArray(list)
			? list.filter((id): id is string => typeof id === 'string' && FILE_ID.test(id))
			: [];
	} catch {
		return [];
	}
}
