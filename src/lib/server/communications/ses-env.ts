import { env } from '$env/dynamic/private';
import { z } from 'zod';

const sesEnvSchema = z.object({
	AWS_SES_REGION: z.string().trim().min(1),
	AWS_SES_ACCESS_KEY_ID: z.string().trim().min(1),
	AWS_SES_SECRET_ACCESS_KEY: z.string().trim().min(1),
	// The SNS topic every per-organization configuration set publishes its delivery events to. One topic
	// feeds the single SQS queue the event consumer drains, so a new contractor needs no new pipeline.
	// Shape-checked because the AWS account id is read back out of it to build identity and tenant ARNs; a
	// malformed or foreign-account topic must fail here rather than produce ARNs that silently authorize
	// nothing.
	AWS_SES_EVENT_SNS_TOPIC_ARN: z
		.string()
		.trim()
		.regex(/^arn:aws:sns:[a-z0-9-]+:\d{12}:[A-Za-z0-9_-]+$/)
});

export type SesEnv = z.infer<typeof sesEnvSchema> & { accountId: string };

// Lazily validated, like getR2Env and getCloudflareDnsEnv: SES is a reserved integration and the app must
// still boot without it. Only Marketing identity provisioning and the Marketing sender need these.
export function getSesEnv(): SesEnv {
	const result = sesEnvSchema.safeParse({
		AWS_SES_REGION: env.AWS_SES_REGION,
		AWS_SES_ACCESS_KEY_ID: env.AWS_SES_ACCESS_KEY_ID,
		AWS_SES_SECRET_ACCESS_KEY: env.AWS_SES_SECRET_ACCESS_KEY,
		AWS_SES_EVENT_SNS_TOPIC_ARN: env.AWS_SES_EVENT_SNS_TOPIC_ARN
	});

	if (!result.success) {
		throw new SesError(
			'Amazon SES is not configured. Set the AWS_SES_* variables to enable Marketing email.',
			null,
			'ses_not_configured'
		);
	}

	return { ...result.data, accountId: result.data.AWS_SES_EVENT_SNS_TOPIC_ARN.split(':')[4] };
}

// The queue name is a fixed part of the provisioned pipeline (docs/marketing-first-release-plan.md), the same
// "derive, never store-then-guess" convention as the per-organization tenant/config-set names.
export function sesEventQueueUrl(env: SesEnv): string {
	return `https://sqs.${env.AWS_SES_REGION}.amazonaws.com/${env.accountId}/ucrm-ses-events`;
}

// The redrive policy on ucrm-ses-events sends a message here after 5 failed receives
// (docs/marketing-first-release-plan.md). Nothing publishes to it directly.
export function sesEventDlqUrl(env: SesEnv): string {
	return `https://sqs.${env.AWS_SES_REGION}.amazonaws.com/${env.accountId}/ucrm-ses-events-dlq`;
}

// Operational email SES Part 4: the customer-reply pipeline, provisioned once for the whole account and kept
// deliberately separate from the delivery-events pipeline above (its own queue, DLQ, and idempotency keys), so
// a stuck reply can never block outgoing mail and vice versa. Fixed names, not env vars, following the same
// "derive, never store-then-guess" convention as the tenant/config-set names.
export const SES_INBOUND_BUCKET_NAME = 'ucrm-ses-inbound-mime';
export const SES_INBOUND_RULE_SET_NAME = 'ucrm-ses-inbound-rules';

export function sesInboundTopicArn(env: SesEnv): string {
	return `arn:aws:sns:${env.AWS_SES_REGION}:${env.accountId}:ucrm-ses-inbound`;
}

export function sesInboundQueueUrl(env: SesEnv): string {
	return `https://sqs.${env.AWS_SES_REGION}.amazonaws.com/${env.accountId}/ucrm-ses-inbound`;
}

// The redrive policy on ucrm-ses-inbound sends a message here after 5 failed receives. Nothing publishes to it
// directly.
export function sesInboundDlqUrl(env: SesEnv): string {
	return `https://sqs.${env.AWS_SES_REGION}.amazonaws.com/${env.accountId}/ucrm-ses-inbound-dlq`;
}

export class SesError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string
	) {
		super(message);
		this.name = 'SesError';
	}
}
