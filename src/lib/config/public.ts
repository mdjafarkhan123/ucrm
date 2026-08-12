import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';
import { z } from 'zod';

const publicEnvSchema = z.object({
	PUBLIC_SUPABASE_URL: z.url(),
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().trim().min(1)
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;

export function getPublicEnv(): PublicEnv {
	const result = publicEnvSchema.safeParse({
		PUBLIC_SUPABASE_URL,
		PUBLIC_SUPABASE_PUBLISHABLE_KEY
	});

	if (!result.success) {
		const missingOrInvalid = result.error.issues.map(
			(issue) => issue.path.join('.') || 'environment'
		);
		throw new Error(`Invalid public environment configuration: ${missingOrInvalid.join(', ')}`);
	}

	return result.data;
}
