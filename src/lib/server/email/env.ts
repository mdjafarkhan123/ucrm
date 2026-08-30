import { env } from '$env/dynamic/private';
import { z } from 'zod';

const emailEnvSchema = z.object({
	BREVO_API_KEY: z.string().trim().min(1),
	SYSTEM_FROM_EMAIL: z.string().trim().toLowerCase().email()
});

export type EmailEnv = z.infer<typeof emailEnvSchema>;

/**
 * Validated lazily (only when an email is actually sent), unlike `getServerEnv`, which
 * `hooks.server.ts` calls eagerly at boot. Brevo is a reserved/optional integration per
 * `docs/ENVIRONMENT.md`, so the app must still start without it configured.
 */
export function getEmailEnv(): EmailEnv {
	const result = emailEnvSchema.safeParse({
		BREVO_API_KEY: env.BREVO_API_KEY,
		SYSTEM_FROM_EMAIL: env.SYSTEM_FROM_EMAIL
	});

	if (!result.success) {
		const missingOrInvalid = result.error.issues.map(
			(issue) => issue.path.join('.') || 'environment'
		);
		throw new Error(`Invalid email environment configuration: ${missingOrInvalid.join(', ')}`);
	}

	return result.data;
}

const inboundWebhookTokenSchema = z.string().trim().min(1);

/**
 * The bearer secret Brevo must send back on every inbound-parse callback. It is stored on the webhook itself
 * (auth: bearer) so the fixed `/api/webhooks/brevo/inbound` route can reject anything that does not present
 * it. Validated lazily and separately from `getEmailEnv` so the ordinary send path never requires it.
 */
export function getBrevoInboundWebhookToken(): string {
	const result = inboundWebhookTokenSchema.safeParse(env.BREVO_INBOUND_WEBHOOK_TOKEN);
	if (!result.success) {
		throw new Error('BREVO_INBOUND_WEBHOOK_TOKEN is not configured.');
	}
	return result.data;
}

/**
 * The absolute URL Brevo posts inbound-parse callbacks to. Built from `APP_URL` so a domain webhook is
 * registered against the same public origin the fixed `/api/webhooks/brevo/inbound` route serves. HTTPS is
 * required outside local development, matching the quote access-link rule.
 */
export function getBrevoInboundWebhookUrl(): string {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin) {
		throw new Error('APP_URL must be set before an inbound webhook can be registered.');
	}
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	return `${origin.origin}/api/webhooks/brevo/inbound`;
}
