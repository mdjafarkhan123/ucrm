import { z } from 'zod';

// The shape Amazon SES publishes to the SNS topic (raw message delivery, so an SQS message body is exactly
// this JSON -- no envelope to unwrap). Only the fields the projector actually reads are validated; everything
// else rides along in payload for the audit trail. See docs/marketing-first-release-plan.md for the
// provisioned pipeline and Memory/campaigns/marketing-growth/parts/M4.md's "Stage 4 decisions" for why.
const sesEventSchema = z
	.object({
		eventType: z.string().trim().min(1).max(80),
		mail: z
			.object({
				messageId: z.string().trim().min(1).max(300),
				timestamp: z.string().optional(),
				// SES echoes every EmailTag back here, keyed by tag name to an array of its values (a
				// configuration set's own name always rides along as 'ses:configuration-set').
				tags: z.record(z.string(), z.array(z.string())).optional()
			})
			.passthrough(),
		bounce: z
			.object({
				bounceType: z.string().optional(),
				timestamp: z.string().optional()
			})
			.passthrough()
			.optional(),
		complaint: z.object({ timestamp: z.string().optional() }).passthrough().optional(),
		delivery: z.object({ timestamp: z.string().optional() }).passthrough().optional(),
		open: z.object({ timestamp: z.string().optional() }).passthrough().optional(),
		click: z.object({ timestamp: z.string().optional() }).passthrough().optional()
	})
	.passthrough();

export type SesEvent = z.infer<typeof sesEventSchema>;

export function parseSesEvent(value: unknown): SesEvent | null {
	const parsed = sesEventSchema.safeParse(value);
	return parsed.success ? parsed.data : null;
}

export function sesEventKey(event: SesEvent): string {
	return `ses:${event.mail.messageId}:${event.eventType}`;
}

/** The configuration set name SES attaches to every event as the 'ses:configuration-set' tag, or null. */
export function sesEventConfigurationSetName(event: SesEvent): string | null {
	return event.mail.tags?.['ses:configuration-set']?.[0] ?? null;
}

/** The first value of a given EmailTag SES echoed back on this event, or null when it was never set. */
export function sesEventTag(event: SesEvent, name: string): string | null {
	return event.mail.tags?.[name]?.[0] ?? null;
}

// The event-type-specific object carries the truer timestamp (when SES actually observed delivery/bounce/
// complaint/open/click); mail.timestamp is only when the API accepted the send.
export function sesEventOccurredAt(event: SesEvent): string | null {
	const specific =
		event.bounce?.timestamp ??
		event.complaint?.timestamp ??
		event.delivery?.timestamp ??
		event.open?.timestamp ??
		event.click?.timestamp;
	return specific ?? event.mail.timestamp ?? null;
}
