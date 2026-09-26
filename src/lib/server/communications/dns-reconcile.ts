import {
	createCloudflareDnsRecord,
	deleteCloudflareDnsRecord,
	listCloudflareDnsRecords,
	updateCloudflareDnsRecord,
	type CloudflareDnsRecord,
	type CloudflareRecordInput
} from './cloudflare-dns';

// The DNS half of managed email-domain activation, shared by the SES operational and
// Marketing reconcilers. These are the rules that keep a contractor's live zone safe -- write only inside the
// managed subdomain, never overwrite a name another service already owns, never proxy a mail record -- so
// they live in one place rather than being copied per provider, where the two copies could drift apart.

// A managed record type set. Anything else already living at a managed subdomain apex means the name is in
// use by another service, so a reconciler refuses rather than guessing.
const MANAGED_RECORD_TYPES = new Set(['TXT', 'CNAME', 'MX']);

export class EmailDomainActivationError extends Error {
	constructor(
		message: string,
		public readonly code: string,
		// retryable: an unknown/ambiguous provider outcome the owner can safely re-run. A conflict
		// (occupied name) is NOT retryable -- it needs a human decision.
		public readonly retryable: boolean
	) {
		super(message);
		this.name = 'EmailDomainActivationError';
	}
}

export type ExpectedRecord = {
	type: string;
	name: string;
	content: string;
	priority?: number;
};

export function normalizeName(name: string): string {
	return name.trim().toLowerCase().replace(/\.$/, '');
}

/**
 * Every provider-issued record for a managed subdomain must live at or under that subdomain. A record whose
 * host name escapes the subdomain would mean writing outside the name UCRM controls, so the run refuses.
 */
export function assertUnderSubdomain(records: ExpectedRecord[], subdomain: string): void {
	const suffix = `.${subdomain}`;
	for (const record of records) {
		if (record.name !== subdomain && !record.name.endsWith(suffix)) {
			throw new EmailDomainActivationError(
				`A provider returned a record for ${record.name}, which is outside ${subdomain}. Activation will not write outside the managed subdomain.`,
				'record_outside_subdomain',
				false
			);
		}
	}
}

/**
 * Refuses a managed subdomain whose apex already serves another service. An MX that is not one this
 * activation owns, or any record type UCRM does not manage, means the name is occupied and a human must
 * decide. `allowedMxTargets` are the provider's own mail hosts, so re-running an activation is safe.
 */
export function assertSubdomainNotOccupied(
	subdomain: string,
	existing: CloudflareDnsRecord[],
	allowedMxTargets: readonly string[]
): void {
	for (const record of existing) {
		const type = record.type.trim().toUpperCase();
		if (!MANAGED_RECORD_TYPES.has(type)) {
			throw new EmailDomainActivationError(
				`${subdomain} already has a ${type} record and appears to be in use. Activation will not overwrite it.`,
				'subdomain_occupied',
				false
			);
		}
		if (type === 'MX') {
			const content = normalizeName(record.content);
			const allowed = allowedMxTargets.some((target) => content === normalizeName(target));
			if (!allowed) {
				throw new EmailDomainActivationError(
					`${subdomain} already routes mail to ${record.content}. Activation will not replace an existing mail route.`,
					'subdomain_occupied',
					false
				);
			}
		}
	}
}

/**
 * Brings one expected record to its desired content in Cloudflare and reports how it settled. Reuses an
 * exact match, updates the single managed record of the same type when its content drifted, creates when
 * absent, and refuses an ambiguous name that has several conflicting records of the same type.
 */
export async function reconcileRecord(
	zoneId: string,
	expected: ExpectedRecord
): Promise<'created' | 'updated' | 'unchanged'> {
	const existing = await listCloudflareDnsRecords(zoneId, expected.name);
	const sameType = existing.filter((record) => record.type.trim().toUpperCase() === expected.type);

	const input: CloudflareRecordInput = {
		type: expected.type,
		name: expected.name,
		content: expected.content,
		proxied: false,
		...(expected.priority != null ? { priority: expected.priority } : {})
	};

	// For MX, the identity is (type, name, priority); for everything else it is (type, name).
	const matches =
		expected.priority != null
			? sameType.filter((record) => record.priority === expected.priority)
			: sameType;

	const exact = matches.find(
		(record) => normalizeName(record.content) === normalizeName(expected.content)
	);
	if (exact) return 'unchanged';

	if (matches.length === 0) {
		await createCloudflareDnsRecord(zoneId, input);
		return 'created';
	}

	if (matches.length === 1) {
		await updateCloudflareDnsRecord(zoneId, matches[0].id, input);
		return 'updated';
	}

	throw new EmailDomainActivationError(
		`${expected.name} has several conflicting ${expected.type} records. Resolve them before activating.`,
		'ambiguous_records',
		false
	);
}

// Cloudflare may return a TXT value wrapped in quotes; compare the value itself.
function recordValue(content: string): string {
	return normalizeName(content.trim().replace(/^"(.*)"$/, '$1'));
}

/**
 * Deletes, at one name, only the records whose exact type and content UCRM would have written. Anything else
 * under the name belongs to someone else and stays. "Already gone" is simply nothing to delete.
 */
export async function deleteOwnedRecords(
	zoneId: string,
	name: string,
	owned: ExpectedRecord[]
): Promise<void> {
	for (const record of await listCloudflareDnsRecords(zoneId, name)) {
		const ours = owned.some(
			(expected) =>
				expected.type === record.type.trim().toUpperCase() &&
				recordValue(expected.content) === recordValue(record.content)
		);
		if (ours) await deleteCloudflareDnsRecord(zoneId, record.id);
	}
}
