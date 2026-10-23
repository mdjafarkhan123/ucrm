import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';

// Messenger Part 5: everything the inbound webhook route and worker need to trust and read a Meta delivery.
// Meta facts: docs/research/messenger-transport-webhooks.md § 4.

// The raw-events table refuses payloads over 1 MiB; refusing earlier keeps a hostile sender from making us
// buffer a large body. Real Messenger deliveries are a few kilobytes.
export const MESSENGER_WEBHOOK_MAX_BODY_BYTES = 1024 * 1024;

function constantTimeEqual(left: string, right: string): boolean {
	const a = Buffer.from(left);
	const b = Buffer.from(right);
	return a.length === b.length && timingSafeEqual(a, b);
}

// GET handshake: Meta proves it was given our verify token and expects its challenge echoed back.
export function messengerHandshakeChallenge(
	params: URLSearchParams,
	verifyToken: string | undefined
): string | null {
	if (!verifyToken) return null;
	const mode = params.get('hub.mode');
	const token = params.get('hub.verify_token');
	const challenge = params.get('hub.challenge');
	if (mode !== 'subscribe' || !token || !challenge) return null;
	if (!constantTimeEqual(token, verifyToken)) return null;
	return challenge;
}

// X-Hub-Signature-256 is HMAC-SHA256 of the exact bytes Meta sent, keyed with the App Secret, as lowercase hex.
export function verifyMessengerSignature(
	body: Uint8Array,
	header: string | null,
	appSecret: string | undefined
): boolean {
	if (!appSecret || !header) return false;
	const match = /^sha256=([0-9a-f]{64})$/i.exec(header.trim());
	if (!match) return false;
	const expected = createHmac('sha256', appSecret).update(body).digest('hex');
	return constantTimeEqual(match[1].toLowerCase(), expected);
}

export function messengerBodySha256(body: Uint8Array): Buffer {
	return createHash('sha256').update(body).digest();
}

// Reads the body up to the cap, stopping as soon as it is exceeded instead of buffering the rest.
export async function readCappedBody(
	request: Request,
	maxBytes = MESSENGER_WEBHOOK_MAX_BODY_BYTES
): Promise<Uint8Array | null> {
	const declared = Number(request.headers.get('content-length'));
	if (Number.isFinite(declared) && declared > maxBytes) return null;
	if (!request.body) return new Uint8Array();

	const reader = request.body.getReader();
	const chunks: Uint8Array[] = [];
	let total = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		total += value.byteLength;
		if (total > maxBytes) {
			await reader.cancel().catch(() => {});
			return null;
		}
		chunks.push(value);
	}
	return new Uint8Array(Buffer.concat(chunks));
}

// --- Reading a saved delivery ------------------------------------------------------------------------------

const metaId = z.string().regex(/^[0-9]{1,32}$/);

const messagingSchema = z
	.object({
		sender: z.object({ id: z.string() }).passthrough(),
		recipient: z.object({ id: z.string() }).passthrough(),
		timestamp: z.number().optional(),
		message: z
			.object({
				mid: z.string().min(1).max(512),
				text: z.string().optional(),
				is_echo: z.boolean().optional(),
				app_id: z.union([z.number(), z.string()]).optional(),
				metadata: z.string().optional(),
				attachments: z.array(z.unknown()).optional()
			})
			.passthrough()
			.optional(),
		delivery: z
			.object({ watermark: z.number(), mids: z.array(z.string()).optional() })
			.passthrough()
			.optional(),
		read: z.object({ watermark: z.number() }).passthrough().optional()
	})
	.passthrough();

const deliverySchema = z
	.object({
		object: z.string(),
		entry: z.array(
			z
				.object({
					id: z.string(),
					messaging: z.array(z.unknown()).optional()
				})
				.passthrough()
		)
	})
	.passthrough();

export type MessengerInboundMessage = {
	pageId: string;
	psid: string;
	mid: string;
	text: string;
	attachmentCount: number;
	sentAt: string | null;
};

const MAX_TEXT_LENGTH = 20_000;

// Pulls the customer messages out of one delivery. Echoes (the Page's own sends) and delivered/read receipts are
// read by parseMessengerPageReports below; anything malformed is skipped, never thrown, so one bad item cannot
// block the rest of a batch Meta sent together.
export function parseMessengerInboundMessages(payload: unknown): MessengerInboundMessage[] {
	const delivery = deliverySchema.safeParse(payload);
	if (!delivery.success || delivery.data.object !== 'page') return [];

	const messages: MessengerInboundMessage[] = [];
	for (const entry of delivery.data.entry) {
		for (const raw of entry.messaging ?? []) {
			const item = messagingSchema.safeParse(raw);
			if (!item.success || !item.data.message || item.data.message.is_echo) continue;
			const pageId = item.data.recipient.id;
			const psid = item.data.sender.id;
			if (!metaId.safeParse(pageId).success || !metaId.safeParse(psid).success) continue;
			if (pageId !== entry.id) continue;

			const sentAt = item.data.timestamp === undefined ? null : new Date(item.data.timestamp);
			messages.push({
				pageId,
				psid,
				mid: item.data.message.mid,
				text: (item.data.message.text ?? '').slice(0, MAX_TEXT_LENGTH),
				attachmentCount: item.data.message.attachments?.length ?? 0,
				sentAt: sentAt && !Number.isNaN(sentAt.getTime()) ? sentAt.toISOString() : null
			});
		}
	}
	return messages;
}

function isoTime(milliseconds: number | undefined): string | null {
	if (milliseconds === undefined) return null;
	const date = new Date(milliseconds);
	return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export type MessengerPageReport =
	| {
			kind: 'echo';
			pageId: string;
			psid: string;
			mid: string;
			text: string;
			/** Our intent ID when the message was sent from UCRM. */
			metadata: string | null;
			appId: string | null;
			sentAt: string | null;
	  }
	| {
			kind: 'delivered' | 'read';
			pageId: string;
			psid: string;
			/** Everything the Page sent this person at or before this time. */
			watermark: string;
			mids: string[];
	  };

// What Meta reports about the Page's own messages (Part 7): echoes of messages the Page sent, from UCRM or
// anywhere else, and delivered/read watermarks from the customer's side.
export function parseMessengerPageReports(payload: unknown): MessengerPageReport[] {
	const delivery = deliverySchema.safeParse(payload);
	if (!delivery.success || delivery.data.object !== 'page') return [];

	const reports: MessengerPageReport[] = [];
	for (const entry of delivery.data.entry) {
		for (const raw of entry.messaging ?? []) {
			const item = messagingSchema.safeParse(raw);
			if (!item.success) continue;
			const { sender, recipient, message, timestamp } = item.data;

			if (message?.is_echo) {
				// An echo runs from the Page to the customer.
				if (sender.id !== entry.id || !metaId.safeParse(recipient.id).success) continue;
				reports.push({
					kind: 'echo',
					pageId: sender.id,
					psid: recipient.id,
					mid: message.mid,
					text: (message.text ?? '').slice(0, MAX_TEXT_LENGTH),
					metadata: message.metadata ?? null,
					appId: message.app_id === undefined ? null : String(message.app_id),
					sentAt: isoTime(timestamp)
				});
				continue;
			}

			const receipt = item.data.read
				? { kind: 'read' as const, watermark: item.data.read.watermark, mids: [] }
				: item.data.delivery
					? {
							kind: 'delivered' as const,
							watermark: item.data.delivery.watermark,
							mids: item.data.delivery.mids ?? []
						}
					: null;
			if (!receipt) continue;
			// A receipt runs from the customer to the Page.
			if (recipient.id !== entry.id || !metaId.safeParse(sender.id).success) continue;
			const watermark = isoTime(receipt.watermark);
			if (!watermark) continue;
			reports.push({
				kind: receipt.kind,
				pageId: recipient.id,
				psid: sender.id,
				watermark,
				mids: receipt.mids.filter((mid) => mid.length > 0 && mid.length <= 512)
			});
		}
	}
	return reports;
}
