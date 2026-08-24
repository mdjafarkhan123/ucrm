import { env } from '$env/dynamic/private';
import { z } from 'zod';

const serverEnvSchema = z.object({
	SUPABASE_SERVICE_ROLE_KEY: z.string().trim().min(1),
	SUPER_ADMIN_EMAIL: z.email(),
	SUPER_ADMIN_PASSWORD_HASH: z.string().trim().min(1),
	SESSION_SECRET: z.string().trim().min(1),
	CLOSURE_CRON_SECRET: z.string().trim().min(1),
	TEAM_INVITATION_WORKER_SECRET: z.string().trim().min(32).optional(),
	COMMUNICATIONS_WORKER_SECRET: z.string().trim().min(32).optional()
});

export type ServerEnv = z.infer<typeof serverEnvSchema>;

export function getServerEnv(): ServerEnv {
	const result = serverEnvSchema.safeParse({
		SUPABASE_SERVICE_ROLE_KEY: env.SUPABASE_SERVICE_ROLE_KEY,
		SUPER_ADMIN_EMAIL: env.SUPER_ADMIN_EMAIL?.trim().toLowerCase(),
		SUPER_ADMIN_PASSWORD_HASH: env.SUPER_ADMIN_PASSWORD_HASH,
		SESSION_SECRET: env.SESSION_SECRET,
		CLOSURE_CRON_SECRET: env.CLOSURE_CRON_SECRET,
		TEAM_INVITATION_WORKER_SECRET: env.TEAM_INVITATION_WORKER_SECRET,
		COMMUNICATIONS_WORKER_SECRET: env.COMMUNICATIONS_WORKER_SECRET
	});

	if (!result.success) {
		const missingOrInvalid = result.error.issues.map(
			(issue) => issue.path.join('.') || 'environment'
		);
		throw new Error(`Invalid server environment configuration: ${missingOrInvalid.join(', ')}`);
	}

	return result.data;
}
