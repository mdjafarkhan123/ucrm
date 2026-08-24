export type CommunicationEmailDomain = {
	id: string;
	domain_name: string;
	lifecycle_state: string;
	ownership_status: string;
	dkim_status: string;
	spf_status: string;
};

export type CommunicationEmailSender = {
	id: string;
	domain_id: string;
	email_address: string;
	display_name: string;
	lifecycle_state: string;
	assigned_user_id: string | null;
	is_organization_default: boolean;
	allows_manual: boolean;
	allows_automated: boolean;
	restriction_reason: string | null;
	created_at: string;
	updated_at: string;
};

export type CommunicationSenders = {
	senders: CommunicationEmailSender[];
	domains: CommunicationEmailDomain[];
};

export type SenderDraft = {
	domain_id: string;
	email_address: string;
	display_name: string;
	assigned_user_id: string | null;
	is_organization_default: boolean;
	allows_manual: boolean;
	allows_automated: boolean;
	enabled: boolean;
};

export class SenderWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {}
	) {
		super(message);
		this.name = 'SenderWriteError';
	}
}

export const communicationSendersKey = ['settings', 'communications', 'senders'] as const;

export async function fetchCommunicationSenders(): Promise<CommunicationSenders> {
	const response = await fetch('/api/settings/communications/senders');
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'Email identities could not be loaded.');
	return result as CommunicationSenders;
}

async function saveSender(url: string, method: 'POST' | 'PATCH', body: object) {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...body, idempotency_key: crypto.randomUUID() })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SenderWriteError(
			result.error ?? 'The email identity could not be saved.',
			result.field_errors ?? {}
		);
	return result as { sender: CommunicationEmailSender };
}

export function createCommunicationSender(draft: SenderDraft) {
	const { enabled: _enabled, ...body } = draft;
	return saveSender('/api/settings/communications/senders', 'POST', body);
}

export function updateCommunicationSender(senderId: string, draft: SenderDraft) {
	const { domain_id: _domainId, email_address: _emailAddress, ...body } = draft;
	return saveSender(`/api/settings/communications/senders/${senderId}`, 'PATCH', body);
}
