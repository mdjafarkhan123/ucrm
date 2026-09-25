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
