import { env } from '$env/dynamic/private';
import { z } from 'zod';

// Server-only Cloudflare DNS adapter for A1-D managed email-domain activation. It exposes thin, idempotent
// primitives -- resolve a zone, read the records at a name, create/update/delete one record -- and NOTHING
// about which records are safe to touch. The reconciler owns the desired-state logic and the mailbox/root
// preservation rules (docs/research/cloudflare-dns-mailbox-preservation-and-brevo-subdomains.md); this file
// only speaks Cloudflare's REST API.
//
// The token is scoped to Zone Read + DNS Edit on managed zones only. It never enters a browser response.

const CLOUDFLARE_API_BASE = 'https://api.cloudflare.com/client/v4';

// A hung DNS call must not hold the reconciler open indefinitely; bound each request with an explicit abort.
// A timeout is an ambiguous (unknown) outcome, never a proven success -- the reconciler re-reads state and
// resumes rather than assuming the write landed.
const CLOUDFLARE_REQUEST_TIMEOUT_MS = 10_000;

const cloudflareEnvSchema = z.object({
	CLOUDFLARE_DNS_API_TOKEN: z.string().trim().min(1)
});

/**
 * Lazily validated, like `getEmailEnv`: Cloudflare DNS is a reserved integration and the app must still boot
 * without it. Only the reconciler, on an owner action, needs the token.
 */
export function getCloudflareDnsEnv(): { CLOUDFLARE_DNS_API_TOKEN: string } {
	const result = cloudflareEnvSchema.safeParse({
		CLOUDFLARE_DNS_API_TOKEN: env.CLOUDFLARE_DNS_API_TOKEN
	});
	if (!result.success) {
		throw new CloudflareDnsError(
			'Cloudflare DNS is not configured (CLOUDFLARE_DNS_API_TOKEN is missing).',
			null,
			'cloudflare_not_configured'
		);
	}
	return result.data;
}

export type CloudflareDnsRecord = {
	id: string;
	type: string;
	name: string;
	content: string;
	ttl: number;
	priority: number | null;
	proxied: boolean;
};

export type CloudflareRecordInput = {
	type: string;
	name: string;
	content: string;
	// Mail and verification records are always DNS-only; the reconciler passes proxied:false. Kept explicit
	// so a caller can never accidentally proxy an SMTP/DKIM host.
	proxied: boolean;
	ttl?: number;
	priority?: number;
};

export class CloudflareDnsError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string
	) {
		super(message);
		this.name = 'CloudflareDnsError';
	}
}

type CloudflareEnvelope<T> = {
	success: boolean;
	errors?: { code?: number; message?: string }[];
	result?: T;
};

async function cloudflareRequest<T>(path: string, init?: RequestInit): Promise<T> {
	const { CLOUDFLARE_DNS_API_TOKEN } = getCloudflareDnsEnv();
	let response: Response;
	try {
		response = await fetch(`${CLOUDFLARE_API_BASE}${path}`, {
			...init,
			signal: AbortSignal.timeout(CLOUDFLARE_REQUEST_TIMEOUT_MS),
			headers: {
				accept: 'application/json',
				authorization: `Bearer ${CLOUDFLARE_DNS_API_TOKEN}`,
				...(init?.body ? { 'content-type': 'application/json' } : {}),
				...init?.headers
			}
		});
	} catch {
		// A network failure or an abort is unknown, not a failure of the write itself. The reconciler treats
		// this as retryable and re-reads state before deciding anything.
		throw new CloudflareDnsError(
			'Cloudflare did not return a DNS outcome.',
			null,
			'cloudflare_network_unknown'
		);
	}

	const text = await response.text();
	let envelope: CloudflareEnvelope<T> | null = null;
	try {
		envelope = text ? (JSON.parse(text) as CloudflareEnvelope<T>) : null;
	} catch {
		envelope = null;
	}

	if (!response.ok || !envelope?.success) {
		const detail = envelope?.errors?.map((error) => error.message).filter(Boolean)[0];
		throw new CloudflareDnsError(
			`Cloudflare rejected the DNS request with status ${response.status}${detail ? `: ${detail}` : ''}.`,
			response.status,
			`cloudflare_http_${response.status}`
		);
	}

	return envelope.result as T;
}

export type CloudflareZone = { id: string; name: string };

/**
 * Resolves the managed zone (id AND apex name) that CONTAINS a domain, by longest suffix. Cloudflare hosts a
 * zone at its registrable apex (e.g. `acme.com`), and every name beneath it — `mail.acme.com`,
 * `reply.test.acme.com` — lives inside that one zone. So we ask Cloudflare for the domain itself, then each
 * parent suffix, from the most specific down to the last registrable pair (never a bare TLD), and take the
 * FIRST match: because we walk most-specific first, the first zone Cloudflare confirms is by construction the
 * longest — the most specific managed zone that contains the domain.
 *
 * A contractor root like `acme.com` matches on the first try (one call, unchanged from exact-apex behavior);
 * a managed subdomain such as `reply.test.acme.com` falls back through `test.acme.com` to `acme.com`. The DNS
 * token can only see the zones UCRM manages, so an unmanaged name resolves to nothing and is refused. This
 * resolver finds the zone only; the reconciler still confines every write to the derived `mail.`/`reply.`
 * subdomains, so widening zone lookup never widens what gets written.
 *
 * The apex NAME is returned alongside the id because callers must fully-qualify provider-issued DNS records:
 * Brevo shortens host names relative to the zone apex, so the reconciler needs the apex to expand them.
 *
 * Cloudflare's `name` filter is an exact match, so a zone whose name is not the exact candidate (a superstring
 * or unrelated match) is ignored, and two active zones sharing one apex is corruption we refuse rather than
 * guess through.
 */
export async function resolveCloudflareZone(domain: string): Promise<CloudflareZone> {
	const normalized = domain.trim().toLowerCase().replace(/\.$/, '');
	const labels = normalized.split('.');

	// i is the index of the first label of the candidate apex; stop at the last two labels so a bare TLD is
	// never queried. Most-specific first means the first confirmed zone is the longest match.
	for (let i = 0; i <= labels.length - 2; i += 1) {
		const candidate = labels.slice(i).join('.');
		const zones = await cloudflareRequest<{ id: string; name: string }[]>(
			`/zones?name=${encodeURIComponent(candidate)}&status=active`
		);
		const exact = zones.filter((zone) => zone.name === candidate);
		if (exact.length === 1) return { id: exact[0].id, name: candidate };
		if (exact.length > 1) {
			throw new CloudflareDnsError(
				`Cloudflare returned more than one active zone named ${candidate}.`,
				null,
				'cloudflare_zone_unresolved'
			);
		}
	}

	throw new CloudflareDnsError(
		`Cloudflare has no managed zone for ${normalized} or any of its parent domains.`,
		null,
		'cloudflare_zone_unresolved'
	);
}

/** Convenience wrapper for callers that only need the zone id. */
export async function resolveCloudflareZoneId(domain: string): Promise<string> {
	return (await resolveCloudflareZone(domain)).id;
}

/**
 * Lists the DNS records at an exact name. The reconciler uses this both to reuse a record it already owns and
 * to detect a conflicting/occupied name it must refuse rather than overwrite.
 */
export async function listCloudflareDnsRecords(
	zoneId: string,
	name: string
): Promise<CloudflareDnsRecord[]> {
	const records = await cloudflareRequest<CloudflareDnsRecord[]>(
		`/zones/${encodeURIComponent(zoneId)}/dns_records?name=${encodeURIComponent(name)}&per_page=100`
	);
	return records.map((record) => ({
		id: record.id,
		type: record.type,
		name: record.name,
		content: record.content,
		ttl: record.ttl,
		priority: record.priority ?? null,
		proxied: record.proxied ?? false
	}));
}

export async function createCloudflareDnsRecord(
	zoneId: string,
	input: CloudflareRecordInput
): Promise<CloudflareDnsRecord> {
	const record = await cloudflareRequest<CloudflareDnsRecord>(
		`/zones/${encodeURIComponent(zoneId)}/dns_records`,
		{ method: 'POST', body: JSON.stringify(input) }
	);
	return {
		id: record.id,
		type: record.type,
		name: record.name,
		content: record.content,
		ttl: record.ttl,
		priority: record.priority ?? null,
		proxied: record.proxied ?? false
	};
}

export async function updateCloudflareDnsRecord(
	zoneId: string,
	recordId: string,
	input: CloudflareRecordInput
): Promise<CloudflareDnsRecord> {
	const record = await cloudflareRequest<CloudflareDnsRecord>(
		`/zones/${encodeURIComponent(zoneId)}/dns_records/${encodeURIComponent(recordId)}`,
		{ method: 'PUT', body: JSON.stringify(input) }
	);
	return {
		id: record.id,
		type: record.type,
		name: record.name,
		content: record.content,
		ttl: record.ttl,
		priority: record.priority ?? null,
		proxied: record.proxied ?? false
	};
}

/**
 * Deletes one record by its Cloudflare id. The reconciler only ever passes an id it resolved from a record it
 * can prove UCRM owns; a record Cloudflare no longer knows is already gone, so a 404 is a success.
 */
export async function deleteCloudflareDnsRecord(zoneId: string, recordId: string): Promise<void> {
	try {
		await cloudflareRequest<{ id: string }>(
			`/zones/${encodeURIComponent(zoneId)}/dns_records/${encodeURIComponent(recordId)}`,
			{ method: 'DELETE' }
		);
	} catch (error) {
		if (error instanceof CloudflareDnsError && error.status === 404) return;
		throw error;
	}
}
