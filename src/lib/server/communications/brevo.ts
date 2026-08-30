import { getBrevoInboundWebhookToken, getEmailEnv } from '$lib/server/email/env';

const BREVO_SEND_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';
const BREVO_API_BASE = 'https://api.brevo.com/v3';

// A hung provider call must not hold a worker slot until it becomes a stale claim. Bound every send with an
// explicit abort; the timeout stays well under the worker's own claim/HTTP budget so an aborted attempt is
// finalized as an ambiguous (submission_unknown) outcome rather than silently stranding the row.
const PROVIDER_SEND_TIMEOUT_MS = 10_000;

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
		public readonly code: string,
		// Brevo's own error envelope ({ code, message }) when it sent one. Callers that must react to a SPECIFIC
		// provider condition (e.g. an inbound webhook refused because the domain is not yet active) match on
		// these rather than the bare HTTP status, so an unrelated 400 is never mistaken for the same case.
		public readonly providerCode: string | null = null,
		public readonly providerMessage: string | null = null
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
		// Read Brevo's error envelope so callers can distinguish specific provider conditions from a bare status.
		let providerCode: string | null = null;
		let providerMessage: string | null = null;
		try {
			const errorBody = await response.text();
			const parsed = errorBody
				? (JSON.parse(errorBody) as { code?: unknown; message?: unknown })
				: null;
			if (parsed && typeof parsed === 'object') {
				providerCode = typeof parsed.code === 'string' ? parsed.code : null;
				providerMessage = typeof parsed.message === 'string' ? parsed.message : null;
			}
		} catch {
			// Non-JSON or empty error body; fall back to the status alone.
		}
		throw new BrevoManagementError(
			`Brevo rejected the domain-management request with status ${response.status}${providerMessage ? `: ${providerMessage}` : ''}.`,
			response.status,
			`brevo_http_${response.status}`,
			providerCode,
			providerMessage
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

// ---------------------------------------------------------------------------------------------------
// Inbound-parse webhook management (A1-D). A receiving domain (reply.<root>) needs exactly one Brevo
// inbound webhook pointing at the fixed, secured `/api/webhooks/brevo/inbound` route. Brevo authenticates
// its callback with the bearer token stored on the webhook, which our route reads from the Authorization
// header -- so the create call MUST use `auth:{type:'bearer',token}`, never a token embedded in the URL.
// docs/research/brevo-return-path-production-patterns.md
// ---------------------------------------------------------------------------------------------------

export type BrevoInboundWebhook = {
	id: number;
	url: string;
	type: string;
	domain: string | null;
	events: string[];
};

function normalizeBrevoWebhook(value: unknown): BrevoInboundWebhook | null {
	if (!value || typeof value !== 'object') return null;
	const webhook = value as Record<string, unknown>;
	if (typeof webhook.id !== 'number' && typeof webhook.id !== 'string') return null;
	return {
		id: Number(webhook.id),
		url: typeof webhook.url === 'string' ? webhook.url : '',
		type: typeof webhook.type === 'string' ? webhook.type : '',
		domain: typeof webhook.domain === 'string' ? webhook.domain : null,
		events: Array.isArray(webhook.events)
			? webhook.events.filter((event): event is string => typeof event === 'string')
			: []
	};
}

export async function listBrevoInboundWebhooks(): Promise<BrevoInboundWebhook[]> {
	const result = (await brevoManagementRequest('/webhooks?type=inbound')) as unknown;
	const raw = Array.isArray(result)
		? result
		: ((result as { webhooks?: unknown[] })?.webhooks ?? []);
	return raw
		.map(normalizeBrevoWebhook)
		.filter((webhook): webhook is BrevoInboundWebhook => webhook !== null);
}

export async function createBrevoInboundWebhook(input: {
	url: string;
	domain: string;
	description: string;
}): Promise<BrevoInboundWebhook> {
	const token = getBrevoInboundWebhookToken();
	const created = (await brevoManagementRequest('/webhooks', {
		method: 'POST',
		body: JSON.stringify({
			type: 'inbound',
			url: input.url,
			domain: input.domain,
			description: input.description,
			events: ['inboundEmailProcessed'],
			auth: { type: 'bearer', token }
		})
	})) as { id: number | string };
	return {
		id: Number(created.id),
		url: input.url,
		type: 'inbound',
		domain: input.domain,
		events: ['inboundEmailProcessed']
	};
}

/**
 * Deletes an inbound webhook by its opaque id. A webhook Brevo no longer knows is already gone, so a 404 is a
 * success -- this makes suspension/closure cleanup safe to retry with only the stored id.
 */
export async function deleteBrevoWebhook(webhookId: string): Promise<void> {
	try {
		await brevoManagementRequest(`/webhooks/${encodeURIComponent(webhookId)}`, {
			method: 'DELETE'
		});
	} catch (error) {
		if (error instanceof BrevoManagementError && error.status === 404) return;
		throw error;
	}
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
			signal: AbortSignal.timeout(PROVIDER_SEND_TIMEOUT_MS),
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
				// Brevo deduplicates an identical retry against this key for 30 minutes. Using the stable
				// delivery-intent UUID makes a database-driven retry safe from double-processing; the tag stays
				// for webhook correlation. This is defense in depth, not an exactly-once guarantee.
				headers: { idempotencyKey: message.intentId },
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
