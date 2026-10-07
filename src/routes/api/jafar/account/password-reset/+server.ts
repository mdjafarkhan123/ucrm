import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerLoginRateLimitBucketKey } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { requestTeamPasswordReset } from '$lib/server/jafar/team-members';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { teamPasswordResetRequestSchema } from '$lib/server/validation/team-member.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// A teammate asks for a password reset link (D1, ADR 0008). The answer is the same whether or not the email
// belongs to a teammate, so this cannot be used to find out who is on the team.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = teamPasswordResetRequestSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		for (const bucket of [
			`reset:${event.getClientAddress()}`,
			`reset-account:${parsed.data.email}`
		]) {
			const rateLimit = await checkRateLimit(client, {
				bucketKey: ownerLoginRateLimitBucketKey(bucket),
				windowSeconds: 900,
				maxAttempts: 5
			});
			if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);
		}

		await requestTeamPasswordReset(client, { email: parsed.data.email, origin: event.url.origin });
		return json({ ok: true });
	} catch (error) {
		console.error('A team password reset could not be requested.', error);
		return json(
			{ error: 'The reset link could not be sent right now. Try again.' },
			{ status: 500 }
		);
	}
};
