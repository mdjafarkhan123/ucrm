import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerLoginRateLimitBucketKey } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TeamMemberError, completeTeamPasswordReset } from '$lib/server/jafar/team-members';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { teamPasswordResetCompleteSchema } from '$lib/server/validation/team-member.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// A teammate sets a new password from their reset link (D1, ADR 0008). They then sign in as usual; their
// other sessions are signed out.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = teamPasswordResetCompleteSchema.safeParse(body);
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
		const rateLimit = await checkRateLimit(client, {
			bucketKey: ownerLoginRateLimitBucketKey(`reset-complete:${event.getClientAddress()}`),
			windowSeconds: 900,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

		await completeTeamPasswordReset(client, {
			token: parsed.data.token,
			password: parsed.data.password
		});
		return json({ ok: true });
	} catch (error) {
		if (error instanceof TeamMemberError) return json({ error: error.message }, { status: 410 });
		console.error('A team password could not be reset.', error);
		return json(
			{ error: 'Your password could not be changed right now. Try again.' },
			{ status: 500 }
		);
	}
};
