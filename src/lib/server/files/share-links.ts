import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer link to a file share (Part 7D), from both ends -- the same shape job_report_access_links
// already proved out. A token is made here, hashed here, and the hash is the only form that ever leaves this
// file towards the database.

const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createFileShareToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all -- a scanner walking
// the URL space never gets to spend a query.
export function fileShareTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export function fileShareUrl(origin: string, token: string) {
	return `${origin}/f/${token}`;
}

/** What `resolve_file_share` hands back. Object keys stay on the server; the page strips them. */
export type ResolvedFileShare = {
	business: { name: string; logo_object_key: string | null };
	expires_at: string;
	files: {
		id: string;
		name: string;
		mime_type: string;
		kind: 'image' | 'video' | 'document';
		size_bytes: number;
		object_key: string;
		thumbnail_object_key: string | null;
	}[];
};

// The public page has no signed-in user. It runs as the service role, whose only file-share privilege is
// the two reader functions. Made once per process.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getFileShareResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}

export async function resolveFileShare(tokenHash: string): Promise<ResolvedFileShare | null> {
	const { data, error } = await getFileShareResolverClient().rpc('resolve_file_share', {
		supplied_token_hash: tokenHash
	});
	// Deliberately not logged with the token: a failure is a broken link or somebody guessing.
	if (error || !data) return null;
	return data as unknown as ResolvedFileShare;
}

// Rate-limit buckets for the public view ping, the same two-key shape the work report link uses.
export function fileShareIpBucketKey(action: string, ipAddress: string) {
	return `file_share_public_${action}_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
}

export function fileShareTokenBucketKey(action: string, tokenHashLiteral: string) {
	return `file_share_public_${action}_token:${tokenHashLiteral.slice(2)}`;
}
