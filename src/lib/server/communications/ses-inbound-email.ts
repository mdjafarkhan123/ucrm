import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { simpleParser, type Attachment, type AddressObject, type HeaderLines } from 'mailparser';
import { z } from 'zod';
import {
	classifyMessageKind,
	parseCandidateAddress,
	type CandidateRecipient,
	type InboundMessageKind
} from './inbound-email';
import { getSesEnv, SES_INBOUND_BUCKET_NAME, type SesEnv } from './ses-env';

// Operational email SES Part 4: parses one SES receipt notification (the S3 receipt action's SNS message --
// raw delivery, so an SQS message body is exactly this JSON, mirroring ses-events.ts) and fetches/parses the
// raw MIME it points to. See docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md for
// why the S3 action, and why the real recipient must come from SES's own trusted envelope `receipt.recipients`
// rather than the MIME To/Cc headers, which SES documents can legitimately differ from the true recipients.

const sesReceiptNotificationSchema = z
	.object({
		notificationType: z.literal('Received'),
		mail: z
			.object({
				messageId: z.string().trim().min(1).max(300),
				timestamp: z.string().optional()
			})
			.passthrough(),
		receipt: z
			.object({
				recipients: z.array(z.string().trim().min(3)).min(1),
				action: z
					.object({
						type: z.literal('S3'),
						bucketName: z.string().trim().min(1),
						objectKey: z.string().trim().min(1)
					})
					.passthrough()
			})
			.passthrough()
	})
	.passthrough();

export type SesReceiptNotification = z.infer<typeof sesReceiptNotificationSchema>;

export function parseSesReceiptNotification(value: unknown): SesReceiptNotification | null {
	const parsed = sesReceiptNotificationSchema.safeParse(value);
	return parsed.success ? parsed.data : null;
}

export function sesInboundEventKey(notification: SesReceiptNotification): string {
	return `ses-inbound:${notification.mail.messageId}`;
}

// The trusted envelope recipients SES itself validated during the SMTP transaction -- never the MIME To/Cc.
export function sesCandidateRecipients(notification: SesReceiptNotification): CandidateRecipient[] {
	return notification.receipt.recipients.flatMap((raw) => {
		const parsed = parseCandidateAddress(raw);
		return parsed ? [parsed] : [];
	});
}

// mailparser's `headers` Map re-structures well-known headers (e.g. content-type becomes {value, params}),
// while the shared classifier reads raw string headers. `headerLines` is the raw,
// unparsed wire text, so building the lowercased/joined shape from it keeps the auto-response and
// delivery-notice heuristics in one shared classifier.
function headersFromHeaderLines(headerLines: HeaderLines): Record<string, string> {
	const normalized: Record<string, string> = {};
	for (const { key, line } of headerLines) {
		const value = line.slice(line.indexOf(':') + 1).trim();
		const lowerKey = key.toLowerCase();
		normalized[lowerKey] = normalized[lowerKey] ? `${normalized[lowerKey]}, ${value}` : value;
	}
	return normalized;
}

function firstAddress(addressObject: AddressObject | AddressObject[] | undefined): {
	address: string;
	name?: string;
} | null {
	const object = Array.isArray(addressObject) ? addressObject[0] : addressObject;
	const entry = object?.value[0];
	if (!entry?.address) return null;
	return { address: entry.address, name: entry.name || undefined };
}

// The {Address, Name} shape record_communication_inbound_message expects, so
// the stored to_recipients/cc_recipients jsonb stays provider-neutral.
function flattenAddresses(
	addressObject: AddressObject | AddressObject[] | undefined
): { Address: string; Name?: string }[] {
	const objects = Array.isArray(addressObject)
		? addressObject
		: addressObject
			? [addressObject]
			: [];
	return objects.flatMap((object) =>
		object.value.flatMap((entry) =>
			entry.address ? [{ Address: entry.address, Name: entry.name || undefined }] : []
		)
	);
}

// SES stamps every email it sends with Message-ID <messageId@email.amazonses.com> (or <region>.amazonses.com),
// while UCRM stores only the bare messageId SendEmail returned. A reply's In-Reply-To names the email it answers,
// so its bare id links the reply to the exact sent email; a non-SES id cannot be one of ours and is dropped.
export function sesInReplyToProviderMessageId(inReplyTo: string | undefined): string | null {
	const match = inReplyTo?.match(/<?([^<>@\s]+)@[a-z0-9.-]*amazonses\.com>?/i);
	return match ? match[1] : null;
}

export type ParsedSesInboundMessage = {
	senderEmail: string;
	senderName: string | undefined;
	toRecipients: { Address: string; Name?: string }[];
	ccRecipients: { Address: string; Name?: string }[];
	subject: string;
	htmlContent: string | undefined;
	textContent: string;
	messageKind: InboundMessageKind;
	inReplyToProviderMessageId: string | null;
	candidateRecipients: CandidateRecipient[];
	attachments: Attachment[];
};

export class SesInboundParseError extends Error {}

// Parses one already-fetched raw MIME buffer against its receipt notification. Fetching the object from S3 is
// the caller's job (the drain worker's dependency-injected `fetchObject`), kept out of this pure function so
// it stays unit-testable without AWS credentials.
export async function parseSesInboundMessage(
	notification: SesReceiptNotification,
	mime: Buffer
): Promise<ParsedSesInboundMessage> {
	const parsed = await simpleParser(mime);
	const sender = firstAddress(parsed.from);
	if (!sender) throw new SesInboundParseError('The message has no usable From address.');

	return {
		senderEmail: sender.address.toLowerCase(),
		senderName: sender.name,
		toRecipients: flattenAddresses(parsed.to),
		ccRecipients: flattenAddresses(parsed.cc),
		subject: parsed.subject ?? '',
		htmlContent: parsed.html === false ? undefined : parsed.html,
		textContent: parsed.text ?? '',
		messageKind: classifyMessageKind(headersFromHeaderLines(parsed.headerLines), sender.address),
		inReplyToProviderMessageId: sesInReplyToProviderMessageId(parsed.inReplyTo),
		candidateRecipients: sesCandidateRecipients(notification),
		attachments: parsed.attachments
	};
}

// One shared S3 client for the SES inbound bucket, using the same AWS_SES_* credentials the IAM grant
// (UcrmOperationalSesInboundAccess) authorizes to read it -- a different account/bucket from Cloudflare R2, so
// this deliberately does not reuse r2.ts's client.
let cachedS3: { client: S3Client; env: SesEnv } | null = null;

function getSesInboundS3(): { client: S3Client; env: SesEnv } {
	if (cachedS3) return cachedS3;
	const env = getSesEnv();
	const client = new S3Client({
		region: env.AWS_SES_REGION,
		credentials: {
			accessKeyId: env.AWS_SES_ACCESS_KEY_ID,
			secretAccessKey: env.AWS_SES_SECRET_ACCESS_KEY
		}
	});
	cachedS3 = { client, env };
	return cachedS3;
}

export async function fetchSesInboundObject(
	bucketName: string,
	objectKey: string
): Promise<Buffer> {
	const { client } = getSesInboundS3();
	const result = await client.send(new GetObjectCommand({ Bucket: bucketName, Key: objectKey }));
	if (!result.Body) throw new SesInboundParseError('The inbound S3 object is empty.');
	return Buffer.from(await result.Body.transformToByteArray());
}

// The inbound attachment worker's SES branch never got a real provider download token -- there is nothing to
// download from SES itself. Its claimed row's provider_download_token is instead the synthetic
// "<objectKey>#<attachmentIndex>" the drain worker built, so importing it means re-fetching the same raw MIME
// object from the one shared inbound bucket and re-parsing it, then picking out that one attachment's bytes.
export async function fetchSesInboundAttachmentBytes(downloadToken: string): Promise<Uint8Array> {
	const separator = downloadToken.lastIndexOf('#');
	if (separator < 0)
		throw new SesInboundParseError('The SES attachment download token is malformed.');
	const objectKey = downloadToken.slice(0, separator);
	const index = Number.parseInt(downloadToken.slice(separator + 1), 10);
	if (!Number.isInteger(index) || index < 0)
		throw new SesInboundParseError('The SES attachment download token is malformed.');

	const mime = await fetchSesInboundObject(SES_INBOUND_BUCKET_NAME, objectKey);
	const parsed = await simpleParser(mime);
	const attachment = parsed.attachments[index];
	if (!attachment)
		throw new SesInboundParseError('The referenced SES attachment no longer parses out.');
	return attachment.content;
}
