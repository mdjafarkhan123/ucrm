import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer link to a payment receipt, from both ends. A token is made here, hashed here, and the hash is
// the only form that ever leaves this file towards the database. Mirrors invoices/access-links.ts so the two
// sides of a receipt link can never disagree about the token's shape.

// 32 random bytes as base64url: 43 URL-safe characters, nothing about the payment or the client encoded.
const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

// Postgres reads `bytea` from JSON as a hex literal. The raw token is never part of this string.
function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createPaymentReceiptAccessToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all.
export function paymentReceiptAccessTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export function paymentReceiptAccessLinkUrl(origin: string, token: string) {
	return `${origin}/r/${token}`;
}

// The public receipt page has no signed-in user, so it runs as the service role, whose only receipt-related
// privilege is one function. Made once per process.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getPaymentReceiptAccessResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}
