import { env } from '$env/dynamic/private';

const VERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

/**
 * Verifies a Cloudflare Turnstile token server-side. When `TURNSTILE_SECRET_KEY` isn't
 * configured, the check is skipped (returns true) so local development works before real
 * keys are added -- the widget itself only renders in the browser when a site key exists.
 */
export async function verifyTurnstileToken(token: string, remoteIp: string) {
	const secretKey = env.TURNSTILE_SECRET_KEY;
	if (!secretKey) return true;

	if (!token) return false;

	try {
		const response = await fetch(VERIFY_URL, {
			method: 'POST',
			headers: { 'content-type': 'application/x-www-form-urlencoded' },
			body: new URLSearchParams({ secret: secretKey, response: token, remoteip: remoteIp })
		});
		const result = (await response.json()) as { success: boolean; 'error-codes'?: string[] };
		// Cloudflare explains a rejection only in `error-codes`. Without it a failure is
		// indistinguishable from a wrong key, a spent token, or an expired one.
		if (result.success !== true)
			console.warn('Spam check rejected the token.', result['error-codes'] ?? []);
		return result.success === true;
	} catch (error) {
		console.error('Could not verify the spam-check token.', error);
		return false;
	}
}
