import { createHash, randomBytes } from 'node:crypto';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer's door to a picture/file an SMS could not carry as real MMS media (Stage 6D-3). Same token
// shape as every other customer link in this codebase (32 random bytes, SHA-256 hashed before it ever
// reaches the database) -- see $lib/server/invoices/access-links.ts for the sibling this mirrors. The one
// difference: this link is issued automatically inside the enqueue command itself, not by a staff "create
// link" click, so the token has to exist *before* that RPC call rather than after.
const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function hexHash(token: string) {
	return createHash('sha256').update(token, 'utf8').digest('hex');
}

// Plain hex (no bytea literal prefix): this hash travels inside the attachment's own JSON payload to the
// enqueue command, which decodes it itself with decode(..., 'hex') rather than relying on PostgREST's bytea
// parameter parsing used by every other access-link table's dedicated RPC parameter.
export function createSmsAttachmentAccessToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHashHex: hexHash(token) };
}

// A token that is not the right shape is answered without touching the database at all -- a scanner walking
// the URL space never gets to spend a query.
export function smsAttachmentAccessTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return `\\x${hexHash(token)}`;
}

export function smsAttachmentAccessLinkUrl(origin: string, token: string) {
	return `${origin}/m/${token}`;
}

// Made ahead of the enqueue RPC call, always, whenever the composer attached a file -- the enqueue command
// decides after the fact whether a real MMS was possible; when it wasn't, this is the link already baked
// into the frozen message body. An unused token (a real MMS was possible after all) is simply never
// persisted -- mirrors how every other access-link table's "caller supplies only the hash" discipline treats
// a token nobody ends up needing.
export function createSmsAttachmentSecureLink() {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin) throw new Error('APP_URL must be set before an SMS attachment can be queued.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	const { token, tokenHashHex } = createSmsAttachmentAccessToken();
	return { tokenHashHex, url: smsAttachmentAccessLinkUrl(origin.origin, token) };
}

// The public file route has no signed-in user, so it cannot use the request's own client. Made once per
// process, mirroring every other access-link resolver client in this codebase.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getSmsAttachmentAccessResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}
