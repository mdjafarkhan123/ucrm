import { env } from '$env/dynamic/private';
import { z } from 'zod';

const r2EnvSchema = z.object({
	R2_ACCOUNT_ID: z.string().trim().min(1),
	R2_ACCESS_KEY_ID: z.string().trim().min(1),
	R2_SECRET_ACCESS_KEY: z.string().trim().min(1),
	R2_BUCKET: z.string().trim().min(1),
	R2_ENDPOINT: z.string().trim().url()
});

export type R2Env = z.infer<typeof r2EnvSchema>;

// R2 is reserved but not required for the app to start (see .env.example), so this parses lazily on first
// use instead of at boot like getServerEnv(). Callers see a clear error only when a route actually needs R2.
export function getR2Env(): R2Env {
	const result = r2EnvSchema.safeParse({
		R2_ACCOUNT_ID: env.R2_ACCOUNT_ID,
		R2_ACCESS_KEY_ID: env.R2_ACCESS_KEY_ID,
		R2_SECRET_ACCESS_KEY: env.R2_SECRET_ACCESS_KEY,
		R2_BUCKET: env.R2_BUCKET,
		R2_ENDPOINT: env.R2_ENDPOINT
	});

	if (!result.success) {
		throw new Error('Cloudflare R2 is not configured. Set the R2_* variables to enable file storage.');
	}

	return result.data;
}
