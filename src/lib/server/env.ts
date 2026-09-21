import { env } from '$env/dynamic/private';
import { z } from 'zod';

const serverEnvSchema = z.object({
	SUPABASE_SERVICE_ROLE_KEY: z.string().trim().min(1),
	SUPER_ADMIN_EMAIL: z.email(),
	SUPER_ADMIN_PASSWORD_HASH: z.string().trim().min(1),
	SESSION_SECRET: z.string().trim().min(1),
	CLOSURE_CRON_SECRET: z.string().trim().min(1),
	TEAM_INVITATION_WORKER_SECRET: z.string().trim().min(32).optional(),
	TEAM_MEMBER_IDENTITY_WORKER_SECRET: z.string().trim().min(32).optional(),
	COMMUNICATIONS_WORKER_SECRET: z.string().trim().min(32).optional(),
	AUTOMATION_WORKER_SECRET: z.string().trim().min(32).optional(),
	GEOCODING_WORKER_SECRET: z.string().trim().min(32).optional(),
	FORM_SUBMISSION_WORKER_SECRET: z.string().trim().min(32).optional(),
	CLIENT_IMPORT_WORKER_SECRET: z.string().trim().min(32).optional(),
	TRUST_HUB_STATUS_CRON_SECRET: z.string().trim().min(32).optional(),
	TRUST_HUB_EVENTS_WEBHOOK_SECRET: z.string().trim().min(32).optional(),
	SMS_PRICE_RECONCILIATION_CRON_SECRET: z.string().trim().min(32).optional(),
	SMS_USAGE_RECONCILIATION_CRON_SECRET: z.string().trim().min(32).optional(),
	FILES_PROCESSING_WORKER_SECRET: z.string().trim().min(32).optional(),
	// Host and port of the ClamAV daemon the upload pipeline streams to. Unset means no scanner, and the
	// pipeline then leaves uploads pending rather than publishing content nothing has checked.
	FILES_SCANNER_HOST: z.string().trim().min(1).optional(),
	FILES_SCANNER_PORT: z.coerce.number().int().positive().optional(),
	MAPBOX_ACCESS_TOKEN: z.string().trim().min(1).optional()
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
		TEAM_MEMBER_IDENTITY_WORKER_SECRET: env.TEAM_MEMBER_IDENTITY_WORKER_SECRET,
		COMMUNICATIONS_WORKER_SECRET: env.COMMUNICATIONS_WORKER_SECRET,
		AUTOMATION_WORKER_SECRET: env.AUTOMATION_WORKER_SECRET,
		GEOCODING_WORKER_SECRET: env.GEOCODING_WORKER_SECRET,
		FORM_SUBMISSION_WORKER_SECRET: env.FORM_SUBMISSION_WORKER_SECRET,
		CLIENT_IMPORT_WORKER_SECRET: env.CLIENT_IMPORT_WORKER_SECRET,
		TRUST_HUB_STATUS_CRON_SECRET: env.TRUST_HUB_STATUS_CRON_SECRET,
		TRUST_HUB_EVENTS_WEBHOOK_SECRET: env.TRUST_HUB_EVENTS_WEBHOOK_SECRET,
		SMS_PRICE_RECONCILIATION_CRON_SECRET: env.SMS_PRICE_RECONCILIATION_CRON_SECRET,
		SMS_USAGE_RECONCILIATION_CRON_SECRET: env.SMS_USAGE_RECONCILIATION_CRON_SECRET,
		FILES_PROCESSING_WORKER_SECRET: env.FILES_PROCESSING_WORKER_SECRET,
		FILES_SCANNER_HOST: env.FILES_SCANNER_HOST,
		FILES_SCANNER_PORT: env.FILES_SCANNER_PORT,
		MAPBOX_ACCESS_TOKEN: env.MAPBOX_ACCESS_TOKEN
	});

	if (!result.success) {
		const missingOrInvalid = result.error.issues.map(
			(issue) => issue.path.join('.') || 'environment'
		);
		throw new Error(`Invalid server environment configuration: ${missingOrInvalid.join(', ')}`);
	}

	return result.data;
}
