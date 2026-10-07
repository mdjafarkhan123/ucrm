import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerLoginRateLimitBucketKey, setOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TeamMemberError, acceptTeamInvitation } from '$lib/server/jafar/team-members';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { teamJoinSchema } from '$lib/server/validation/team-member.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// A teammate accepts their invitation: name and password, then they are signed in (D1, ADR 0008). Open to
// visitors; the secret single-use link in the body is the only thing that grants anything.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = teamJoinSchema.safeParse(body);
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
			bucketKey: ownerLoginRateLimitBucketKey(`join:${event.getClientAddress()}`),
			windowSeconds: 900,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

		const member = await acceptTeamInvitation(client, {
			token: parsed.data.token,
			fullName: parsed.data.full_name,
			password: parsed.data.password
		});
		await setOwnerSession(event, member.email, member.memberId);
		return json({ ok: true });
	} catch (error) {
		if (error instanceof TeamMemberError) return json({ error: error.message }, { status: 410 });
		console.error('A team invitation could not be accepted.', error);
		return json(
			{ error: 'Your account could not be set up right now. Try again.' },
			{ status: 500 }
		);
	}
};
