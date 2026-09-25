import MessageValidator from 'sns-validator';
import { z } from 'zod';

// Verifies an Amazon SNS HTTPS delivery with AWS's own validator (`sns-validator`, aws/aws-js-sns-message-validator):
// the signing certificate must come from SNS in our region, and the signature must match the message. Only then is
// the topic compared, so a genuine message from somebody else's topic is refused too.

const snsEnvelopeSchema = z.object({
	Type: z.enum(['Notification', 'SubscriptionConfirmation', 'UnsubscribeConfirmation']),
	MessageId: z.string().min(1),
	TopicArn: z.string().min(1),
	SubscribeURL: z.string().optional()
});

export type SnsEnvelope = z.infer<typeof snsEnvelopeSchema>;

export type SnsSignatureCheck = (message: Record<string, unknown>) => Promise<void>;

function escapeRegExp(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function snsHost(region: string): string {
	return `sns.${region}.amazonaws.com`;
}

export function awsSnsSignatureCheck(region: string): SnsSignatureCheck {
	const validator = new MessageValidator(new RegExp(`^${escapeRegExp(snsHost(region))}$`));
	return (message) =>
		new Promise((resolve, reject) =>
			validator.validate(message, (error) => (error ? reject(error) : resolve()))
		);
}

/**
 * Returns the envelope when the body is a genuine SNS message from `topicArn`, otherwise null. Never says why:
 * a caller only needs to refuse.
 */
export async function verifySnsMessage(
	body: string,
	topicArn: string,
	checkSignature: SnsSignatureCheck
): Promise<SnsEnvelope | null> {
	let raw: unknown;
	try {
		raw = JSON.parse(body);
	} catch {
		return null;
	}
	if (!raw || typeof raw !== 'object') return null;

	const envelope = snsEnvelopeSchema.safeParse(raw);
	if (!envelope.success || envelope.data.TopicArn !== topicArn) return null;

	try {
		await checkSignature(raw as Record<string, unknown>);
	} catch {
		return null;
	}
	return envelope.data;
}

/**
 * The validator checks the signature, not where SubscribeURL points. Confirming means fetching that URL, so it
 * must be SNS in our region over HTTPS -- never an arbitrary address a message carried.
 */
export function trustedSubscribeUrl(subscribeUrl: string | undefined, region: string): URL | null {
	if (!subscribeUrl) return null;
	try {
		const url = new URL(subscribeUrl);
		return url.protocol === 'https:' && url.host === snsHost(region) ? url : null;
	} catch {
		return null;
	}
}
