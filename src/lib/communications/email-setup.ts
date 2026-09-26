import { httpError } from '$lib/http-error';

// Where the business's email lives today. Tells Jafar whether DNS access is likely to be needed and from whom.
export const MAILBOX_PROVIDERS = [
	{ value: 'google_workspace', label: 'Google Workspace' },
	{ value: 'microsoft_365', label: 'Microsoft 365' },
	{ value: 'godaddy', label: 'GoDaddy' },
	{ value: 'hostinger', label: 'Hostinger' },
	{ value: 'other', label: 'Somewhere else' },
	{ value: 'none', label: 'No business email yet' }
] as const;

export type MailboxProvider = (typeof MAILBOX_PROVIDERS)[number]['value'];

export function mailboxProviderLabel(value: string) {
	return MAILBOX_PROVIDERS.find((provider) => provider.value === value)?.label ?? value;
}

// none: nothing asked yet (or the last ask was withdrawn); waiting: asked, Jafar has not started;
// setting_up: Jafar has started; ready: a verified sending domain exists; declined: Jafar closed it with a note.
export type EmailSetupState = 'none' | 'waiting' | 'setting_up' | 'ready' | 'declined';

export type EmailSetupRequest = {
	id: string;
	root_domain: string;
	mailbox_provider: MailboxProvider;
	note: string | null;
	created_at: string;
	closed_note: string | null;
	closed_at: string | null;
};

export type EmailSetup = {
	state: EmailSetupState;
	request: EmailSetupRequest | null;
};

export const emailSetupKey = ['settings', 'communications', 'email-setup'] as const;

export class EmailSetupWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {}
	) {
		super(message);
		this.name = 'EmailSetupWriteError';
	}
}

export async function fetchEmailSetup(): Promise<EmailSetup> {
	const response = await fetch('/api/settings/communications/email-setup');
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'Your email setup could not be loaded.');
	return result as EmailSetup;
}

async function write(url: string, body: object) {
	const response = await fetch(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new EmailSetupWriteError(
			result.error ?? 'Your email setup could not be updated.',
			result.field_errors ?? {}
		);
	return result as EmailSetup;
}

export function requestEmailSetup(draft: {
	root_domain: string;
	mailbox_provider: MailboxProvider;
	note: string;
}) {
	return write('/api/settings/communications/email-setup', draft);
}

export function cancelEmailSetup(requestId: string) {
	return write(`/api/settings/communications/email-setup/${requestId}/cancel`, {});
}
