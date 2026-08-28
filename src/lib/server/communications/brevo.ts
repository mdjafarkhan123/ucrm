import { getEmailEnv } from '$lib/server/email/env';

const BREVO_SEND_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';
const BREVO_API_BASE = 'https://api.brevo.com/v3';

export type BrevoDnsRecord = {
	type: string;
	host_name: string;
	value: string;
	status: boolean;
};

export type BrevoDomainConfiguration = {
	domain: string;
	verified: boolean;
	authenticated: boolean;
	dns_records: BrevoDnsRecord[];
};

type BrevoDomainConfigurationResponse = Omit<BrevoDomainConfiguration, 'dns_records'> & {
	dns_records?: unknown;
};

export type BrevoDomain = {
	id: string;
	domain_name: string;
	verified: boolean;
	authenticated: boolean;
};

export class BrevoManagementError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string
	) {
		super(message);
		this.name = 'BrevoManagementError';
	}
}

async function brevoManagementRequest(path: string, init?: RequestInit): Promise<unknown> {
	const { BREVO_API_KEY } = getEmailEnv();
	let response: Response;
	try {
		response = await fetch(`${BREVO_API_BASE}${path}`, {
			...init,
			headers: {
				accept: 'application/json',
				'api-key': BREVO_API_KEY,
				...(init?.body ? { 'content-type': 'application/json' } : {}),
				...init?.headers
			}
		});
	} catch {
		throw new BrevoManagementError(
			'Brevo did not return a domain-management outcome.',
			null,
			'brevo_network_unknown'
		);
	}

	if (!response.ok) {
		throw new BrevoManagementError(
			`Brevo rejected the domain-management request with status ${response.status}.`,
			response.status,
			`brevo_http_${response.status}`
		);
	}

	if (response.status === 204) return null;
	const text = await response.text();
	return text ? JSON.parse(text) : null;
}

function isBrevoDnsRecord(value: unknown): value is BrevoDnsRecord {
	if (!value || typeof value !== 'object') return false;
	const record = value as Record<string, unknown>;
	return (
		typeof record.type === 'string' &&
		typeof record.host_name === 'string' &&
		typeof record.value === 'string' &&
		typeof record.status === 'boolean'
	);
}

function normalizeBrevoDnsRecords(value: unknown): BrevoDnsRecord[] {
	const records = Array.isArray(value)
		? value
		: value && typeof value === 'object'
			? Object.values(value)
			: [];
	return records.filter(isBrevoDnsRecord);
}

export async function createBrevoDomain(domainName: string) {
	return (await brevoManagementRequest('/senders/domains', {
		method: 'POST',
		body: JSON.stringify({ name: domainName })
	})) as { id: string; domain_name: string; dns_records?: BrevoDnsRecord[] };
}

export async function listBrevoDomains(): Promise<BrevoDomain[]> {
	const result = (await brevoManagementRequest('/senders/domains')) as { domains?: BrevoDomain[] };
	return result.domains ?? [];
}

export async function getBrevoDomain(domainName: string) {
	const configuration = (await brevoManagementRequest(
		`/senders/domains/${encodeURIComponent(domainName)}`
	)) as BrevoDomainConfigurationResponse;
	return {
		...configuration,
		dns_records: normalizeBrevoDnsRecords(configuration.dns_records)
	};
}

export async function authenticateBrevoDomain(domainName: string) {
	return brevoManagementRequest(`/senders/domains/${encodeURIComponent(domainName)}/authenticate`, {
		method: 'PUT'
	});
}

export async function deleteBrevoDomain(domainName: string) {
	await brevoManagementRequest(`/senders/domains/${encodeURIComponent(domainName)}`, {
		method: 'DELETE'
	});
}

/**
 * Deletes a Brevo sender-domain by its opaque provider id rather than its name. Used by the purge
 * cleanup path, which deliberately keeps no domain name -- only the opaque id -- so it lists Brevo's
 * domains, matches the id, and deletes by the name Brevo reports. A domain Brevo no longer knows is
 * already gone, so an unmatched id is a success, not an error.
 */
export async function deleteBrevoDomainById(providerDomainId: string) {
	const domains = await listBrevoDomains();
	const match = domains.find((domain) => String(domain.id) === providerDomainId);
	if (!match) return;
	await deleteBrevoDomain(match.domain_name);
}

export async function createBrevoSender(input: { email: string; name: string }) {
	return (await brevoManagementRequest('/senders', {
		method: 'POST',
		body: JSON.stringify(input)
	})) as { id: number; dkimError?: boolean; spfError?: boolean };
}

export type BrevoSender = {
	id: number;
	email: string;
	name: string;
	active: boolean;
};

export async function listBrevoSenders(domain?: string): Promise<BrevoSender[]> {
	const query = domain ? `?domain=${encodeURIComponent(domain)}` : '';
	const result = (await brevoManagementRequest(`/senders${query}`)) as {
		senders?: BrevoSender[];
	};
	return result.senders ?? [];
}

export async function updateBrevoSender(
	senderId: number,
	input: { email?: string; name?: string }
) {
	await brevoManagementRequest(`/senders/${senderId}`, {
		method: 'PUT',
		body: JSON.stringify(input)
	});
}

export async function deleteBrevoSender(senderId: number) {
	await brevoManagementRequest(`/senders/${senderId}`, { method: 'DELETE' });
}

export class BrevoInboundAttachmentError extends Error {
	constructor(
		message: string,
		public readonly status: number | null
	) {
		super(message);
		this.name = 'BrevoInboundAttachmentError';
	}
}

export async function downloadBrevoInboundAttachment(downloadToken: string): Promise<Uint8Array> {
	const { BREVO_API_KEY } = getEmailEnv();
	let response: Response;
	try {
		response = await fetch(
			`${BREVO_API_BASE}/inbound/attachments/${encodeURIComponent(downloadToken)}`,
			{ headers: { 'api-key': BREVO_API_KEY } }
		);
	} catch {
		throw new BrevoInboundAttachmentError('Brevo did not return the attachment download.', null);
	}

	if (!response.ok)
		throw new BrevoInboundAttachmentError(
			`Brevo rejected the attachment download with status ${response.status}.`,
			response.status
		);

	return new Uint8Array(await response.arrayBuffer());
}

export class OperationalEmailSubmissionError extends Error {
	constructor(
		message: string,
		public readonly outcome: 'retry' | 'cancelled' | 'submission_unknown',
		public readonly code: string
	) {
		super(message);
		this.name = 'OperationalEmailSubmissionError';
	}
}

export type OperationalEmail = {
	from: { email: string; name?: string };
	// A forward can address up to 10 external recipients at once (docs/contractor-email-contract.md §
	// Recipients, forwarding, and portal access); every other send path keeps passing a single recipient.
	to: { email: string; name?: string } | { email: string; name?: string }[];
	replyTo?: { email: string; name?: string };
	subject: string;
	htmlContent: string;
	textContent: string;
	intentId: string;
	attachments?: { name: string; content: string }[];
};

export async function sendOperationalEmail(
	message: OperationalEmail
): Promise<{ messageId: string }> {
	const { BREVO_API_KEY } = getEmailEnv();
	let response: Response;
	try {
		response = await fetch(BREVO_SEND_ENDPOINT, {
			method: 'POST',
			headers: {
				accept: 'application/json',
				'content-type': 'application/json',
				'api-key': BREVO_API_KEY
			},
			body: JSON.stringify({
				sender: message.from,
				to: Array.isArray(message.to) ? message.to : [message.to],
				...(message.replyTo ? { replyTo: message.replyTo } : {}),
				subject: message.subject,
				htmlContent: message.htmlContent,
				textContent: message.textContent,
				...(message.attachments && message.attachments.length > 0
					? { attachment: message.attachments }
					: {}),
				tags: [`ucrm:email:${message.intentId}`]
			})
		});
	} catch {
		throw new OperationalEmailSubmissionError(
			'Brevo did not return a submission outcome.',
			'submission_unknown',
			'brevo_network_unknown'
		);
	}

	if (!response.ok) {
		const retryable = response.status === 408 || response.status === 429 || response.status >= 500;
		throw new OperationalEmailSubmissionError(
			`Brevo rejected the request with status ${response.status}.`,
			retryable ? 'retry' : 'cancelled',
			`brevo_http_${response.status}`
		);
	}

	const body = (await response.json()) as { messageId?: string };
	if (!body.messageId)
		throw new OperationalEmailSubmissionError(
			'Brevo accepted the request without returning a message identifier.',
			'submission_unknown',
			'brevo_missing_message_id'
		);
	return { messageId: body.messageId };
}
