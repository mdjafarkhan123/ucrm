import { timingSafeEqual } from 'node:crypto';
import { z } from 'zod';

const eventSchema = z.object({
	event: z.string().trim().min(1).max(80),
	id: z.union([z.number().int(), z.string().trim().min(1)]).optional(),
	['message-id']: z.string().trim().min(1).max(300).optional(),
	ts_event: z.number().int().nonnegative().optional(),
	tags: z.array(z.string()).optional()
}).passthrough();

export type BrevoWebhookEvent = z.infer<typeof eventSchema>;

export function bearerMatches(authorization: string | null, expectedToken: string | undefined) {
	if (!expectedToken) return false;
	const token = authorization?.match(/^Bearer (.+)$/i)?.[1];
	if (!token) return false;
	const expected = Buffer.from(expectedToken);
	const provided = Buffer.from(token);
	return expected.length === provided.length && timingSafeEqual(expected, provided);
}

export function parseBrevoWebhookEvent(value: unknown): BrevoWebhookEvent | null {
	const parsed = eventSchema.safeParse(value);
	return parsed.success ? parsed.data : null;
}

export function eventKey(event: BrevoWebhookEvent) {
	return [event.event, event.id ?? '', event['message-id'] ?? '', event.ts_event ?? ''].join(':');
}

export function intentIdFromTags(tags: string[] | undefined) {
	const tag = tags?.find((value) => value.startsWith('ucrm:email:'));
	return tag?.slice('ucrm:email:'.length) ?? null;
}
