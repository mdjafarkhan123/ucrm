import { json } from '@sveltejs/kit';
import { emailBucketPart, enforceAuthRateLimits } from '$lib/server/security/rate-limit';
import { contractorLoginSchema, zodAuthFieldErrors } from '$lib/server/validation/auth.schema';

// Password guessing is slowed two ways, the way Auth0's brute-force protection does it: one email tried from
// one address, and everything tried from one address. Keying the first on the address as well means a
// stranger hammering someone's email locks out only themselves, not the real owner signing in from home.
const LOGIN_WINDOW_SECONDS = 900;
const LOGIN_TRIES_PER_EMAIL_AND_ADDRESS = 10;
const LOGIN_TRIES_PER_ADDRESS = 50;

export async function POST(event) {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please enter your email and password.' }, { status: 400 });
	}

	const parsed = contractorLoginSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodAuthFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const address = event.getClientAddress();
	const limited = await enforceAuthRateLimits([
		{
			bucketKey: `login:email:${emailBucketPart(parsed.data.email)}:${address}`,
			windowSeconds: LOGIN_WINDOW_SECONDS,
			maxAttempts: LOGIN_TRIES_PER_EMAIL_AND_ADDRESS
		},
		{
			bucketKey: `login:address:${address}`,
			windowSeconds: LOGIN_WINDOW_SECONDS,
			maxAttempts: LOGIN_TRIES_PER_ADDRESS
		}
	]);
	if (limited) return limited;

	const { error } = await event.locals.supabase.auth.signInWithPassword(parsed.data);
	if (error) {
		return json({ error: 'The email or password is not correct.' }, { status: 401 });
	}

	return json({ ok: true });
}

export async function DELETE(event) {
	const { error } = await event.locals.supabase.auth.signOut();
	if (error) {
		console.error('Contractor sign out failed.', error);
		return json({ error: 'We could not sign you out. Please try again.' }, { status: 500 });
	}

	return json({ ok: true });
}
