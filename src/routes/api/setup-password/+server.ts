import { createHash } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	setupPasswordSchema,
	setupPasswordTokenSchema,
	zodSetupPasswordFieldErrors
} from '$lib/server/validation/setup-password.schema';

const INVALID_LINK_MESSAGE = 'This setup link is invalid or has expired.';

function hashToken(token: string) {
	return createHash('sha256').update(token).digest('hex');
}

function maskEmail(email: string) {
	const [local, domain] = email.split('@');
	if (!domain) return email;
	const visible = local.slice(0, 1);
	return `${visible}${'*'.repeat(Math.max(local.length - 1, 3))}@${domain}`;
}

export const GET: RequestHandler = async (event) => {
	const parsedToken = setupPasswordTokenSchema.safeParse(event.url.searchParams.get('token'));
	if (!parsedToken.success) return json({ valid: false });

	try {
		const client = getOwnerSupabaseClient();

		const rateLimit = await checkRateLimit(client, {
			bucketKey: `setup_password_get:${event.getClientAddress()}`,
			windowSeconds: 300,
			maxAttempts: 30
		});
		if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

		const { data: link, error } = await client
			.from('platform_onboarding_application_setup_links')
			.select('intended_email, expires_at, consumed_at')
			.eq('token_hash', hashToken(parsedToken.data))
			.maybeSingle();
		if (error) throw error;

		const isUsable =
			Boolean(link) && !link!.consumed_at && new Date(link!.expires_at).getTime() > Date.now();
		if (!isUsable) return json({ valid: false });

		return json({ valid: true, email_hint: maskEmail(link!.intended_email) });
	} catch (error) {
		console.error('Could not check the administrator setup link.', error);
		return json({ valid: false });
	}
};

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please enter your email and a new password.' }, { status: 400 });
	}

	const parsed = setupPasswordSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodSetupPasswordFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	const { token, email, password } = parsed.data;

	try {
		const client = getOwnerSupabaseClient();

		const rateLimit = await checkRateLimit(client, {
			bucketKey: `setup_password_post:${event.getClientAddress()}`,
			windowSeconds: 900,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

		const tokenHash = hashToken(token);

		// One atomic UPDATE claims the link (token + not consumed + not expired + recipient email,
		// all in the same WHERE clause) so it cannot be split into a racing check-then-write pair.
		const { data: consumeRows, error: consumeError } = await client.rpc(
			'consume_onboarding_application_setup_link',
			{ target_token_hash: tokenHash, target_email: email }
		);
		if (consumeError) throw consumeError;
		const consumeResult = consumeRows?.[0];

		if (!consumeResult?.consumed) {
			// The claim failed -- do a read-only lookup, purely to give a specific reason, without
			// mutating anything (a wrong email must stay retryable, not burn the one-time link).
			const { data: link } = await client
				.from('platform_onboarding_application_setup_links')
				.select('intended_email, expires_at, consumed_at')
				.eq('token_hash', tokenHash)
				.maybeSingle();
			const isOtherwiseUsable =
				Boolean(link) && !link!.consumed_at && new Date(link!.expires_at).getTime() > Date.now();
			if (isOtherwiseUsable && link!.intended_email !== email) {
				return json(
					{
						error: 'Please review the highlighted fields.',
						field_errors: { email: "That email doesn't match this setup link." }
					},
					{ status: 422 }
				);
			}
			return json({ error: INVALID_LINK_MESSAGE }, { status: 401 });
		}

		const { error: updateUserError } = await client.auth.admin.updateUserById(
			consumeResult.administrator_user_id,
			{ password }
		);
		if (updateUserError) throw updateUserError;

		return json({ ok: true });
	} catch (error) {
		console.error('Could not complete administrator password setup.', error);
		return json(
			{ error: 'We could not set your password. Try requesting a new link.' },
			{ status: 500 }
		);
	}
};
