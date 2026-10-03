import { httpError } from '$lib/http-error';
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
	}[];
	progress: { done: number; total: number };
	next: { key: string; title: string; status: SetupSectionStatus } | null;
	delivery: { state: 'collecting' };
	/** Whether the signed-in person gets setup reminder emails. */
	reminder_emails_on: boolean;
};

export type SetupSectionData = {
	key: string;
	/** The section's questions as the published setup version asks them now. */
	section: SetupSection;
	answers: SetupAnswers;
	/** What the CRM already knows, offered for questions nobody has answered yet. */
	suggestions: Record<string, string>;
	status: SetupSectionStatus;
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
