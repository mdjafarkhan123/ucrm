import { env } from '$env/dynamic/private';
import { createQuoteAccessToken, quoteAccessLinkUrl } from '$lib/server/quotes/access-links';

export function createQuoteEmailAccessLink() {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin) throw new Error('APP_URL must be set before quote email can be queued.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	const { token, tokenHash } = createQuoteAccessToken();
	return { tokenHash, url: quoteAccessLinkUrl(origin.origin, token) };
}
