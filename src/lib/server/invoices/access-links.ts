import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer link to an invoice, from both ends. A token is made here, hashed here, and the hash is the
// only form that ever leaves this file towards the database. Keeping both halves in one module is what stops
// the two sides from drifting into hashing different things. Issuing links is Part 6b; the maker lives here
// now so the maker and the reader can never disagree about the token's shape.

// 32 random bytes as base64url: 43 URL-safe characters, no escaping, and nothing about the invoice, the
// organization or the recipient encoded in it.
const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

// Postgres reads `bytea` from JSON as a hex literal. The raw token is never part of this string.
function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createInvoiceAccessToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all — a scanner walking
// the URL space never gets to spend a query.
export function invoiceAccessTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export function invoiceAccessLinkUrl(origin: string, token: string) {
	return `${origin}/i/${token}`;
}

// The public page has no signed-in user, so it cannot use the request's own client: `anon` has no grant on
// anything here. It runs as the service role, whose only invoice-related privilege is one function. Made once
// per process, because the customer page opens as often as an email is read.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getInvoiceAccessResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}
