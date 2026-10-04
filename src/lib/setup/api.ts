import { httpError } from '$lib/http-error';
import type { SetupCheck, SetupConfirmation } from '$lib/setup/check';
import type { SetupClientReview } from '$lib/setup/review';
import type { SetupHelpAnswer } from '$lib/setup/help';
import type {
	SetupAnswers,
	SetupAvailability,
	SetupSection,
	SetupSectionStatus
} from '$lib/setup/catalogue';

// Client setup reads and writes. The wizard autosaves each answer on its own, so there is no revision to
// carry and no Save button to press (docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md).

export type SetupSummary = {
	welcome_seen: boolean;
	sections: {
		key: string;
		title: string;
		description: string;
		status: SetupSectionStatus;
		answered: number;
		total: number;
		/** C3b: Uplift's review of this section on the newest send; null before it was sent. */
		review: SetupClientReview | null;
	}[];
	progress: { done: number; total: number };
	/** `returned`: a section Uplift sent back, to change. */
	next: { key: string; title: string; status: SetupSectionStatus; returned: boolean } | null;
	/** Sections Uplift sent back on the newest send. */
	returned_count: number;
	delivery:
		| { state: 'collecting' }
		| { state: 'sent'; number: number; submitted_at: string; submitted_by_name: string };
	/** Whether the signed-in person gets setup reminder emails. */
	reminder_emails_on: boolean;
};

export type SetupSectionData = {
	key: string;
	/** The section's questions as the published setup version asks them now. */
	section: SetupSection;
	answers: SetupAnswers;
	/** Earlier sections' answers this section's "show only if" rules read, for questions asked now. */
	earlier_answers: SetupAnswers;
	/** What the CRM already knows, offered for questions nobody has answered yet. */
	suggestions: Record<string, string>;
	/** The business's country and currency as known now, for amount answers. */
	country: string | null;
	currency: string | null;
	status: SetupSectionStatus;
	/** C3b: Uplift's review of this section on the newest send; null before it was sent. */
	review: SetupClientReview | null;
	/** C3c: what Uplift filled in for questions here answered "I need Uplift's help", by question. */
	help_answers: Record<string, SetupHelpAnswer>;
};

export type SetupAnswerWrite = {
	fact_key: string;
	/** null clears the answer. */
	availability: SetupAvailability | null;
	value?: string | null;
	note?: string | null;
};

// The user id is part of both keys: the query client outlives sign-out, and setup belongs to whoever is
// signed in.
export const setupSummaryKey = (userId: string | null) => ['setup', 'summary', userId] as const;
export const setupSectionKey = (userId: string | null, section: string) =>
	['setup', 'section', userId, section] as const;

export async function fetchSetupSummary(): Promise<SetupSummary> {
	const response = await fetch('/api/setup');
	if (!response.ok) throw httpError(response, 'Setup could not be loaded.');
	return response.json();
}

export async function fetchSetupSection(section: string): Promise<SetupSectionData> {
	const response = await fetch(`/api/setup/sections/${encodeURIComponent(section)}`);
	if (!response.ok) throw httpError(response, 'This part of setup could not be loaded.');
	return response.json();
}

export async function markSetupWelcomeSeen(): Promise<void> {
	const response = await fetch('/api/setup/welcome', { method: 'POST' });
	if (!response.ok) throw httpError(response, 'Setup could not be updated.');
}

export async function setSetupReminderEmails(emailsOn: boolean): Promise<void> {
	const response = await fetch('/api/setup/reminders', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ emails_on: emailsOn })
	});
	if (!response.ok) throw httpError(response, 'Your reminder choice could not be saved.');
}

export type SetupWriteFailure = Error & { status: number; fieldErrors: Record<string, string> };

async function writeFailure(response: Response, fallback: string): Promise<SetupWriteFailure> {
	const body = (await response.json().catch(() => null)) as {
		error?: string;
		field_errors?: Record<string, string>;
	} | null;
	const error = httpError(response, body?.error ?? fallback) as SetupWriteFailure;
	error.fieldErrors = body?.field_errors ?? {};
	return error;
}

// `keepalive` lets the last autosave finish when the page is being closed or put in the background, which
// is how a phone normally leaves a form.
export async function saveSetupAnswers(
	answers: SetupAnswerWrite[],
	options: { keepalive?: boolean } = {}
): Promise<void> {
	const response = await fetch('/api/setup/answers', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ answers }),
		keepalive: options.keepalive
	});
	if (!response.ok) throw await writeFailure(response, 'Your answer could not be saved.');
}

export async function setSetupSectionDone(section: string, done: boolean): Promise<void> {
	const response = await fetch(`/api/setup/sections/${encodeURIComponent(section)}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ done })
	});
	if (!response.ok) throw await writeFailure(response, 'This section could not be updated.');
}

/** B13: Check and send to Uplift — every task read back, the confirmations, and the newest send. */
export type SetupCheckData = SetupCheck & {
	confirmations: SetupConfirmation[];
	sent: { number: number; submitted_at: string; submitted_by_name: string } | null;
	/** C3c: what Uplift filled in for questions answered "I need Uplift's help", by question. */
	help_answers: Record<string, SetupHelpAnswer>;
};

export const setupCheckKey = (userId: string | null) => ['setup', 'check', userId] as const;

export async function fetchSetupCheck(): Promise<SetupCheckData> {
	const response = await fetch('/api/setup/check');
	if (!response.ok) throw httpError(response, 'Your answers could not be loaded.');
	return response.json();
}

/** Sends setup to Uplift. `previousNumber` is the newest send the page showed, 0 for none. */
export async function sendSetupToUplift(
	confirmed: string[],
	previousNumber: number
): Promise<{ submission_number: number; submitted_at: string }> {
	const response = await fetch('/api/setup/check', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ confirmed, previous_number: previousNumber })
	});
	if (!response.ok) throw await writeFailure(response, 'Your setup could not be sent.');
	return response.json();
}

/** One file of a photo or file answer (client onboarding A5c). Mirrors `$lib/server/setup/files`. */
export type SetupFileInfo = {
	id: string;
	name: string;
	mime_type: string;
	size_bytes: number;
	/** `removed`: trashed in the File library, or gone. */
	state: 'checking' | 'ready' | 'refused' | 'removed';
	thumb_url: string | null;
	problem: string | null;
};

export const setupFilesKey = (userId: string | null, ids: readonly string[]) =>
	['setup', 'files', userId, ...ids] as const;

export async function fetchSetupFiles(ids: readonly string[]): Promise<SetupFileInfo[]> {
	const response = await fetch(`/api/setup/files?ids=${ids.map(encodeURIComponent).join(',')}`);
	if (!response.ok) throw httpError(response, 'These files could not be loaded.');
	return ((await response.json()) as { files: SetupFileInfo[] }).files;
}

/** Where to open one file of the organization's setup answers: a photo shows, anything else downloads. */
export const setupFileHref = (id: string) => `/api/setup/files/${encodeURIComponent(id)}`;

/**
 * Reserves a File for one file a client is adding to a photo or file answer. The bytes then go to
 * `upload_url` with exactly `mime_type`.
 */
export async function startSetupFileUpload(
	factKey: string,
	file: File,
	/** A5e: the file box of a list question. */
	fieldKey?: string
): Promise<{ file_id: string; mime_type: string; upload_url: string }> {
	const response = await fetch('/api/setup/files', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			fact_key: factKey,
			...(fieldKey ? { field_key: fieldKey } : {}),
			file_name: file.name,
			mime_type: file.type,
			size_bytes: file.size
		})
	});
	if (!response.ok) {
		const failure = await writeFailure(response, 'That file could not be uploaded.');
		// The reason under a field is the one worth reading: "This question takes photos: JPG, PNG…".
		throw new Error(Object.values(failure.fieldErrors)[0] ?? failure.message);
	}
	return response.json();
}

/**
 * One protected document of a setup answer (client onboarding B9b): a phone bill, a tax letter. Mirrors
 * `$lib/server/setup/protected-documents`. It has no preview: only the business owner can open it, by download.
 */
export type ProtectedDocumentInfo = {
	id: string;
	name: string;
	size_bytes: number;
	/** `removed`: deleted, or not one of this question's documents. */
	state: 'uploading' | 'checking' | 'ready' | 'refused' | 'removed';
	problem: string | null;
	uploaded_at: string | null;
	delete_after: string | null;
};

export type ProtectedDocumentEvent = {
	action:
		| 'uploaded'
		| 'refused'
		| 'opened'
		| 'removed'
		| 'deletion_scheduled'
		| 'deleted_by_uplift'
		| 'expired';
	who: string;
	at: string;
};

export const protectedDocumentsKey = (userId: string | null, ids: readonly string[]) =>
	['setup', 'protected-documents', userId, ...ids] as const;

/** The documents, and whether the person asking may open them — the business owner only. */
export async function fetchProtectedDocuments(
	ids: readonly string[]
): Promise<{ documents: ProtectedDocumentInfo[]; can_open: boolean }> {
	const response = await fetch(
		`/api/setup/protected-documents?ids=${ids.map(encodeURIComponent).join(',')}`
	);
	if (!response.ok) throw httpError(response, 'These files could not be loaded.');
	return response.json();
}

/** Downloads one protected document; the opening is recorded in its history. */
export const protectedDocumentHref = (id: string) =>
	`/api/setup/protected-documents/${encodeURIComponent(id)}`;

/** Reserves a protected document. The bytes then go to `upload_url` with exactly `mime_type`. */
export async function startProtectedDocumentUpload(
	factKey: string,
	file: File
): Promise<{ document_id: string; mime_type: string; upload_url: string }> {
	const response = await fetch('/api/setup/protected-documents', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			fact_key: factKey,
			file_name: file.name,
			mime_type: file.type,
			size_bytes: file.size
		})
	});
	if (!response.ok) {
		const failure = await writeFailure(response, 'That file could not be uploaded.');
		throw new Error(Object.values(failure.fieldErrors)[0] ?? failure.message);
	}
	return response.json();
}

/** Reports the bytes arrived, which hands the document to the virus check. */
export async function finishProtectedDocumentUpload(id: string): Promise<void> {
	const response = await fetch(`${protectedDocumentHref(id)}/complete`, { method: 'POST' });
	if (!response.ok) {
		const failure = await writeFailure(response, 'That upload could not be finished.');
		throw new Error(Object.values(failure.fieldErrors)[0] ?? failure.message);
	}
}

/** Deletes a protected document for good. Its history stays. */
export async function removeProtectedDocument(id: string): Promise<void> {
	const response = await fetch(protectedDocumentHref(id), { method: 'DELETE' });
	if (!response.ok) throw await writeFailure(response, 'That file could not be removed.');
}

/** A document's history, from the setup page's route or Jafar's. */
export async function fetchProtectedDocumentHistory(
	url: string
): Promise<ProtectedDocumentEvent[]> {
	const response = await fetch(url);
	if (!response.ok) throw httpError(response, 'This history could not be loaded.');
	return ((await response.json()) as { history: ProtectedDocumentEvent[] }).history;
}
