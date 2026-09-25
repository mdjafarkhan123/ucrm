import { z } from 'zod';

// Brevo sends null for absent names, reply references, and body variants. Normalize only those
// documented nullable fields to our existing optional values at the provider boundary.
const addressSchema = z.object({
	Address: z.string().trim().min(3).max(320),
	Name: z
		.string()
		.trim()
		.max(160)
		.nullish()
		.transform((value) => value ?? undefined)
});

const attachmentSchema = z
	.object({
		Name: z.string().trim().min(1).max(255),
		ContentType: z.string().trim().min(1).max(127),
		ContentLength: z.number().int().nonnegative(),
		ContentID: z.string().optional(),
		DownloadToken: z.string().trim().min(1)
	})
	.passthrough();

const inboundItemSchema = z
	.object({
		MessageId: z.string().trim().min(1).max(300).optional(),
		Uuid: z.array(z.string().trim().min(1)).optional(),
		// Brevo sends InReplyTo as "" (not null) for a message that is not a reply. Treat empty and
		// whitespace-only the same as absent, alongside the documented null case.
		InReplyTo: z
			.string()
			.trim()
			.max(300)
			.nullish()
			.transform((value) => value || undefined),
		From: addressSchema,
		To: z.array(addressSchema).default([]),
		Cc: z.array(addressSchema).default([]),
		SentAtDate: z.string().optional(),
		Subject: z.string().trim().max(998).default(''),
		RawHtmlBody: z
			.string()
			.nullish()
			.transform((value) => value ?? undefined),
		RawTextBody: z
			.string()
			.nullish()
			.transform((value) => value ?? undefined),
		Attachments: z.array(attachmentSchema).default([]),
		Headers: z.record(z.string(), z.union([z.string(), z.array(z.string())])).default({})
	})
	.passthrough();

const inboundWebhookSchema = z.object({ items: z.array(inboundItemSchema).min(1) });

export type BrevoInboundAddress = z.infer<typeof addressSchema>;
export type BrevoInboundAttachment = z.infer<typeof attachmentSchema>;
export type BrevoInboundItem = z.infer<typeof inboundItemSchema>;

export function parseBrevoInboundWebhook(value: unknown): BrevoInboundItem[] | null {
	const parsed = inboundWebhookSchema.safeParse(value);
	return parsed.success ? parsed.data.items : null;
}

export type CandidateRecipient = { address: string; local_part: string; domain_name: string };

// Shared by every provider's candidate-recipient resolution: a raw address string in, a normalized
// {address, local_part, domain_name} out, or null for something that is not a plausible address at all.
export function parseCandidateAddress(rawAddress: string): CandidateRecipient | null {
	const address = rawAddress.trim().toLowerCase();
	const at = address.lastIndexOf('@');
	if (at <= 0 || at === address.length - 1) return null;
	return { address, local_part: address.slice(0, at), domain_name: address.slice(at + 1) };
}

// To first, then Cc, in the order Brevo supplied them -- the resolution function walks this array
// looking for the first address on one of our own verified receiving domains.
export function candidateRecipients(item: BrevoInboundItem): CandidateRecipient[] {
	return [...item.To, ...item.Cc].flatMap((recipient) => {
		const parsed = parseCandidateAddress(recipient.Address);
		return parsed ? [parsed] : [];
	});
}

function normalizedHeaders(headers: BrevoInboundItem['Headers']): Record<string, string> {
	const normalized: Record<string, string> = {};
	for (const [key, value] of Object.entries(headers)) {
		normalized[key.toLowerCase()] = Array.isArray(value) ? value.join(', ') : value;
	}
	return normalized;
}

export type InboundMessageKind = 'reply' | 'auto_response' | 'delivery_notice';

// Auto-response and delivery-notice detection reads only the standard signals other mail systems already
// set, not a UCRM-invented heuristic. Shared by every provider so the heuristics live in exactly one
// place -- callers just supply their own lowercased headers map and sender address.
export function classifyMessageKind(
	headers: Record<string, string>,
	senderAddress: string
): InboundMessageKind {
	const sender = senderAddress.trim().toLowerCase();

	if (
		headers['auto-submitted']?.toLowerCase().startsWith('auto-') ||
		headers['x-autoreply'] !== undefined ||
		headers['x-autorespond'] !== undefined ||
		headers['precedence']?.toLowerCase() === 'auto_reply'
	) {
		return 'auto_response';
	}

	if (
		headers['content-type']?.toLowerCase().includes('multipart/report') ||
		sender.startsWith('mailer-daemon@') ||
		sender.startsWith('postmaster@')
	) {
		return 'delivery_notice';
	}

	return 'reply';
}

export function classifyInboundMessageKind(item: BrevoInboundItem): InboundMessageKind {
	return classifyMessageKind(normalizedHeaders(item.Headers), item.From.Address);
}

export const INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES = 20 * 1024 * 1024;

// Gmail's documented blocked-extension list is the reference standard for dangerous attachment types.
export const DANGEROUS_ATTACHMENT_EXTENSIONS = new Set([
	'ade',
	'adp',
	'apk',
	'appx',
	'appxbundle',
	'bat',
	'cab',
	'chm',
	'cmd',
	'com',
	'cpl',
	'dll',
	'dmg',
	'ex',
	'ex_',
	'exe',
	'hta',
	'ins',
	'isp',
	'iso',
	'jar',
	'js',
	'jse',
	'lib',
	'lnk',
	'mde',
	'msc',
	'msi',
	'msix',
	'msixbundle',
	'msp',
	'mst',
	'nsh',
	'pif',
	'ps1',
	'scr',
	'sct',
	'shb',
	'sys',
	'vb',
	'vbe',
	'vbs',
	'vxd',
	'wsc',
	'wsf',
	'wsh'
]);

// MessageId is the primary dedupe key; Brevo's own event Uuid is the fallback when a provider omits
// it, and a random id is the last resort so one malformed item never blocks every other item's ingest.
export function inboundEventDedupeKey(item: BrevoInboundItem): string {
	return item.MessageId ?? item.Uuid?.[0] ?? crypto.randomUUID();
}

export function attachmentExtension(fileName: string): string {
	const dot = fileName.lastIndexOf('.');
	return dot < 0 ? '' : fileName.slice(dot + 1).toLowerCase();
}
