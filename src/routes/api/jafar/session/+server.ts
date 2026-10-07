import { json } from '@sveltejs/kit';
import {
	clearOwnerSession,
	isOwnerEmail,
	ownerLoginRateLimitBucketKey,
	recordOwnerLoginAttempt,
	setOwnerSession,
	verifyOwnerCredentials
} from '$lib/server/auth/owner';
import { verifyTeammateCredentials } from '$lib/server/jafar/team-members';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { ownerLoginSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export async function POST(event) {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please enter your email and password.' }, { status: 400 });
	}

	const parsed = ownerLoginSchema.safeParse(body);
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
		const rateLimitClient = getOwnerSupabaseClient();
		const rateLimit = await checkRateLimit(rateLimitClient, {
			bucketKey: ownerLoginRateLimitBucketKey(event.getClientAddress()),
			windowSeconds: 900,
			maxAttempts: 8
		});
		if (!rateLimit.allowed) {
			await recordOwnerLoginAttempt('rate_limited');
			return rateLimitedResponse(rateLimit.retryAfterSeconds);
		}
		// Teammates share this sign-in, so guessing is also capped per account, not only per address.
		const accountLimit = await checkRateLimit(rateLimitClient, {
			bucketKey: ownerLoginRateLimitBucketKey(`account:${parsed.data.email.trim().toLowerCase()}`),
			windowSeconds: 900,
			maxAttempts: 10
		});
		if (!accountLimit.allowed) {
			await recordOwnerLoginAttempt('rate_limited');
			return rateLimitedResponse(accountLimit.retryAfterSeconds);
		}

		// The owner's own email is checked only against the configured owner password; any other email
		// can only be an active teammate (ADR 0008).
		if (isOwnerEmail(parsed.data.email)) {
			if (!verifyOwnerCredentials(parsed.data.email, parsed.data.password)) {
				await recordOwnerLoginAttempt('failed');
				return json({ error: 'The email or password is not correct.' }, { status: 401 });
			}
			await setOwnerSession(event, parsed.data.email);
		} else {
			const teammate = await verifyTeammateCredentials(
				rateLimitClient,
				parsed.data.email,
				parsed.data.password
			);
			if (!teammate) {
				await recordOwnerLoginAttempt('failed');
				return json({ error: 'The email or password is not correct.' }, { status: 401 });
			}
			await setOwnerSession(event, teammate.email, teammate.memberId);
		}

		await recordOwnerLoginAttempt('succeeded');
		return json({ ok: true });
	} catch (error) {
		console.error('Platform owner login is unavailable.', error);
		return json({ error: 'Platform owner login is not configured.' }, { status: 503 });
	}
}

export async function DELETE(event) {
	await clearOwnerSession(event);
	return json({ ok: true });
}
