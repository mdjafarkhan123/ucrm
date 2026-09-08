import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer link to a job's work report, from both ends -- the same shape invoice_access_links already
// proved out. A token is made here, hashed here, and the hash is the only form that ever leaves this file
// towards the database.

const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createJobReportAccessToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all -- a scanner walking
// the URL space never gets to spend a query.
export function jobReportAccessTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export function jobReportAccessLinkUrl(origin: string, token: string) {
	return `${origin}/w/${token}`;
}

// The public page has no signed-in user, so it cannot use the request's own client: `anon` has no grant on
// anything here. It runs as the service role, whose only job-report-related privilege is the two functions
// granted to it. Made once per process, because the customer page opens as often as an email is read.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getJobReportAccessResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}

// Rate-limit buckets for the public path, the same two-key shape invoices and quotes already use: an address
// alone would punish a whole office sharing one connection, and a token alone would let a spread-out caller
// walk the URL space unhindered.
export function jobReportAccessIpBucketKey(action: string, ipAddress: string) {
	return `job_report_public_${action}_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
}

export function jobReportAccessTokenBucketKey(action: string, tokenHashLiteral: string) {
	return `job_report_public_${action}_token:${tokenHashLiteral.slice(2)}`;
}
