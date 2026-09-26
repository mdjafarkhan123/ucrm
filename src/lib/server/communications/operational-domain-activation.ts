import { listCloudflareDnsRecords, resolveCloudflareZone } from './cloudflare-dns';
import {
	assertSubdomainNotOccupied,
	assertUnderSubdomain,
	deleteOwnedRecords,
	EmailDomainActivationError,
	reconcileRecord,
	type ExpectedRecord
} from './dns-reconcile';
import {
	associateSesTenantResource,
	deleteSesIdentity,
	disassociateSesTenantResource,
	ensureSesEventDestination,
	getSesIdentity,
	putSesIdentityMailFrom,
	sesConfigurationSetArn,
	sesIdentityArn,
	sesInboundMxTarget,
	sesMailFromMxTarget
} from './ses';
import {
	ensureSesConfigurationSet,
	findExistingDomainId,
	nextLifecycleState,
	normalizeRootDomain,
	operationalConfigurationSetName,
	readDomainHistory,
	reconcileSesIdentity,
	reconcileSesTenant,
	sesDkimRecords,
	sesMailFromRecords,
	sesStatusToDns,
	sesTenantName,
	toStoredDnsRecords,
	upsertDomainRow,
	type DnsStatus,
	type OwnerClient
} from './ses-domain-identity';
import { reconcileReplyIngestion, routeSendingRepliesToSes } from './operational-reply-ingestion';

export { EmailDomainActivationError } from './dns-reconcile';

// Managed operational ("everyday email") domain activation on Amazon SES. A desired-state saga like the
// Marketing reconciler: every provider step is idempotent, no database transaction is held across an AWS or
// Cloudflare call, and a Recheck safely resumes after DNS propagation or a partial provider failure. The owner
// route owns authorization, rate limiting, idempotency receipts, and the audit event.
//
// Safety rules (docs/contractor-email-contract.md "Domain provisioning and sender identity"):
//   - Sending and receiving live on INDEPENDENTLY derived subdomains, mail.<root> and reply.<root>. The custom
//     MAIL FROM is bounce.mail.<root>, which neither sends nor receives.
//   - Only records under mail.<root> and reply.<root> are ever written. Root MX, root mailbox authentication,
//     and any unexpected occupied subdomain record are never overwritten.
//
// Customer replies are part of the same Set up. The reply.<root> SES identity is created here; once SES has
// verified it (usually on the first Check after the DKIM records propagate), the same pass creates the receipt
// rule, points reply.<root>'s MX at SES, and records the receiving row (operational-reply-ingestion.ts). SES
// will not receive for an unverified domain, so the MX is never written before that. mail.<root> receives too,
// once its own identity is verified, for mail clients that reply to From instead of Reply-To
// (docs/contractor-email-contract.md, "Conversations and replies").

const SENDING_LABEL = 'mail';
const RECEIVING_LABEL = 'reply';
const MAIL_FROM_LABEL = 'bounce';

export type OperationalSendingSummary = {
	domain_id: string;
	domain_name: string;
	mail_from_domain: string;
	purpose: 'sending';
	lifecycle_state: 'pending_dns' | 'verified' | 'unhealthy';
	provider_verified: boolean;
	provider_authenticated: boolean;
	ownership_status: DnsStatus;
	dkim_status: DnsStatus;
	spf_status: DnsStatus;
	records_written: number;
	tenant_name: string;
	configuration_set_name: string;
	event_destination_ready: boolean;
};

export type OperationalReceivingSummary = {
	domain_name: string;
	// The SES identity's verification: with Easy DKIM the CNAMEs are the ownership proof.
	ses_identity_status: DnsStatus;
	records_written: number;
	// The receiving row. Null until the reply identity is verified and the MX has been written.
	domain_id: string | null;
	lifecycle_state: string | null;
	inbound_mx_status: DnsStatus | null;
};

export type OperationalActivationResult = {
	root_domain: string;
	zone_id: string;
	sending: OperationalSendingSummary;
	receiving: OperationalReceivingSummary;
};

function deriveOperationalDomains(rootDomain: string) {
	const root = normalizeRootDomain(rootDomain);
	// Derived independently: reply.<root> is never a function of mail.<root>.
	const sending = `${SENDING_LABEL}.${root}`;
	return {
		root,
		sending,
		receiving: `${RECEIVING_LABEL}.${root}`,
		mailFrom: `${MAIL_FROM_LABEL}.${sending}`
	};
}

export async function activateOperationalDomain(input: {
	client: OwnerClient;
	organizationId: string;
	rootDomain: string;
}): Promise<OperationalActivationResult> {
	return reconcileOperationalDomain({
		client: input.client,
		organizationId: input.organizationId,
		...deriveOperationalDomains(input.rootDomain)
	});
}

/**
 * Re-runs the same reconciliation for a sending row. Everything is idempotent, so a Recheck is simply another
 * pass: it re-reads SES, repairs any record that drifted, and re-derives the health values.
 */
export async function recheckOperationalDomain(input: {
	client: OwnerClient;
	organizationId: string;
	domainId: string;
}): Promise<OperationalActivationResult> {
	const { data, error } = await input.client
		.from('communication_email_domains')
		.select('id, domain_name, dns_zone, purpose')
		.eq('organization_id', input.organizationId)
		.eq('id', input.domainId)
		.neq('lifecycle_state', 'removed')
		.maybeSingle();
	if (error) throw error;
	if (!data || data.purpose !== 'sending') {
		throw new EmailDomainActivationError(
			'Everyday email sending domain on Amazon SES was not found.',
			'operational_domain_not_found',
			false
		);
	}
	if (!data.dns_zone) {
		throw new EmailDomainActivationError(
			'This sending domain has no recorded root domain. Run Set up again.',
			'operational_domain_missing_root',
			false
		);
	}

	const domains = deriveOperationalDomains(data.dns_zone);
	if (domains.sending !== data.domain_name) {
		throw new EmailDomainActivationError(
			'This sending domain does not match its recorded root domain.',
			'operational_domain_mismatch',
			false
		);
	}

	return reconcileOperationalDomain({
		client: input.client,
		organizationId: input.organizationId,
		...domains
	});
}

async function reconcileOperationalDomain(input: {
	client: OwnerClient;
	organizationId: string;
	root: string;
	sending: string;
	receiving: string;
	mailFrom: string;
}): Promise<OperationalActivationResult> {
	const { client, organizationId, root, sending, receiving, mailFrom } = input;

	// Claim checks first, so a name owned by another organization stops the run before any provider call.
	const [sendingId, receivingId] = await Promise.all([
		findExistingDomainId(client, organizationId, sending, 'sending'),
		findExistingDomainId(client, organizationId, receiving, 'receiving')
	]);

	// Each provider call is a ~0.4 s round trip, and run one after another they made Check take ~10 s. Calls
	// that do not depend on each other now run together; every step that must precede another (MAIL FROM
	// before DNS, occupancy before any write, records before the read-back) still waits for it.
	const configurationSetName = operationalConfigurationSetName(organizationId);
	const [{ id: zoneId }, tenant, eventDestinationReady, sendingIdentity, receivingIdentity] =
		await Promise.all([
			// The managed zone that CONTAINS the root, by longest suffix.
			resolveCloudflareZone(root),
			reconcileSesTenant(client, organizationId),
			// Without the event destination the operational dispatcher would send successfully and never learn
			// what happened to it -- the same call Marketing's configuration set reuses as-is.
			ensureSesConfigurationSet(configurationSetName).then(() =>
				ensureSesEventDestination(configurationSetName)
			),
			reconcileSesIdentity(sending),
			reconcileSesIdentity(receiving)
		]);

	// Point the identity at the custom MAIL FROM before writing DNS, so SES is already watching for the records
	// when they appear. BehaviorOnMxFailure falls back to amazonses.com meanwhile, so nothing bounces while the
	// records propagate.
	if (sendingIdentity.mailFromDomain !== mailFrom) {
		await putSesIdentityMailFrom(sending, mailFrom);
	}

	const sendingRecords = [
		...sesDkimRecords(sendingIdentity, sending),
		...sesMailFromRecords(mailFrom)
	];
	const receivingRecords = sesDkimRecords(receivingIdentity, receiving);
	assertUnderSubdomain(sendingRecords, sending);
	assertUnderSubdomain(receivingRecords, receiving);

	// Occupancy: none of the three names may already serve another service. SES's own mail hosts are allowed
	// so a re-run and a Recheck are safe.
	const [sendingExisting, mailFromExisting, receivingExisting] = await Promise.all([
		listCloudflareDnsRecords(zoneId, sending),
		listCloudflareDnsRecords(zoneId, mailFrom),
		listCloudflareDnsRecords(zoneId, receiving)
	]);
	assertSubdomainNotOccupied(sending, sendingExisting, [sesInboundMxTarget()]);
	assertSubdomainNotOccupied(mailFrom, mailFromExisting, [sesMailFromMxTarget()]);
	assertSubdomainNotOccupied(receiving, receivingExisting, [sesInboundMxTarget()]);

	// The two record sets sit under different names, so writing them together cannot collide. Authorizing the
	// tenant to send from this identity with this configuration set runs on every pass rather than only on the
	// run that created them, so a Recheck repairs a missing association.
	const [sendingWritten, receivingWritten] = await Promise.all([
		writeRecords(zoneId, sendingRecords),
		writeRecords(zoneId, receivingRecords),
		associateSesTenantResource(tenant.tenantName, sesIdentityArn(sending)),
		associateSesTenantResource(tenant.tenantName, sesConfigurationSetArn(configurationSetName))
	]);

	// Read the identities back after the records are in place: SES re-checks on its own schedule, so this
	// reports the truth at this moment and a later Recheck picks up the change.
	const [settledRead, settledReceivingRead] = await Promise.all([
		getSesIdentity(sending),
		getSesIdentity(receiving)
	]);
	const settled = settledRead ?? sendingIdentity;
	const settledReceiving = settledReceivingRead ?? receivingIdentity;

	// With Easy DKIM the three CNAMEs ARE the proof of domain control, so ownership and DKIM share one status.
	const dkimStatus = sesStatusToDns(settled.dkimStatus);
	const spfStatus = sesStatusToDns(settled.mailFromStatus);
	const providerVerified = settled.verifiedForSending;
	const providerAuthenticated = settled.dkimSigningEnabled && dkimStatus === 'passing';
	// The contract gates sending on SES verification plus passing Easy DKIM. MAIL FROM is reported but not
	// required: until it resolves, SES falls back to its own MAIL FROM and mail still flows.
	const ready = providerVerified && providerAuthenticated;

	// Replies to the From address: only once SES has verified mail.<root>, since SES will not receive for an
	// unverified identity. Occupancy was asserted above, before anything was written.
	const fromReplies = ready ? await routeSendingRepliesToSes(zoneId, sending) : null;

	const now = new Date().toISOString();
	const history = await readDomainHistory(client, sendingId);
	const lifecycleState = nextLifecycleState(ready, history);

	const domainId = await upsertDomainRow(client, sendingId, {
		organization_id: organizationId,
		purpose: 'sending',
		domain_name: sending,
		dns_zone: root,
		provider: 'ses',
		// SES has no opaque domain id: the identity IS the domain name, so the ARN is the stable handle worth
		// storing for sending and for cleanup.
		provider_domain_id: sesIdentityArn(sending),
		provider_verified: providerVerified,
		provider_authenticated: providerAuthenticated,
		ownership_status: dkimStatus,
		dkim_status: dkimStatus,
		spf_status: spfStatus,
		// inbound_mx_status stays 'unchecked' on a sending row (purpose_health_check).
		inbound_mx_status: 'unchecked',
		dns_records: toStoredDnsRecords(
			fromReplies ? [...sendingRecords, fromReplies.record] : sendingRecords
		),
		lifecycle_state: lifecycleState,
		last_checked_at: now,
		// First verification stamps the clock; a later recheck keeps the original date, so warm-up and
		// "verified since" stay honest.
		verified_at: ready ? (history.verifiedAt ?? now) : history.verifiedAt,
		updated_at: now
	});

	const receivingReady =
		settledReceiving.dkimSigningEnabled &&
		sesStatusToDns(settledReceiving.dkimStatus) === 'passing';
	const replies = receivingReady
		? await reconcileReplyIngestion({
				client,
				organizationId,
				root,
				receiving,
				zoneId,
				receivingId
			})
		: null;

	return {
		root_domain: root,
		zone_id: zoneId,
		sending: {
			domain_id: domainId,
			domain_name: sending,
			mail_from_domain: mailFrom,
			purpose: 'sending',
			lifecycle_state: lifecycleState,
			provider_verified: providerVerified,
			provider_authenticated: providerAuthenticated,
			ownership_status: dkimStatus,
			dkim_status: dkimStatus,
			spf_status: spfStatus,
			records_written: sendingWritten + (fromReplies?.written ?? 0),
			tenant_name: tenant.tenantName,
			configuration_set_name: configurationSetName,
			event_destination_ready: eventDestinationReady
		},
		receiving: {
			domain_name: receiving,
			ses_identity_status: sesStatusToDns(settledReceiving.dkimStatus),
			records_written: receivingWritten + (replies?.records_written ?? 0),
			...(replies
				? {
						domain_id: replies.domain_id,
						lifecycle_state: replies.lifecycle_state,
						inbound_mx_status: replies.inbound_mx_status
					}
				: await readReceivingRow(client, receivingId))
		}
	};
}

async function writeRecords(zoneId: string, records: ExpectedRecord[]): Promise<number> {
	let written = 0;
	for (const record of records) {
		if ((await reconcileRecord(zoneId, record)) !== 'unchanged') written += 1;
	}
	return written;
}

async function readReceivingRow(
	client: OwnerClient,
	receivingId: string | null
): Promise<
	Pick<OperationalReceivingSummary, 'domain_id' | 'lifecycle_state' | 'inbound_mx_status'>
> {
	if (!receivingId) return { domain_id: null, lifecycle_state: null, inbound_mx_status: null };
	const { data, error } = await client
		.from('communication_email_domains')
		.select('lifecycle_state, inbound_mx_status')
		.eq('id', receivingId)
		.maybeSingle();
	if (error) throw error;
	return {
		domain_id: receivingId,
		lifecycle_state: data?.lifecycle_state ?? null,
		inbound_mx_status: (data?.inbound_mx_status as DnsStatus | undefined) ?? null
	};
}

/**
 * Undoes everything Set up created for one organization's everyday email, at the providers only; the owner
 * route finalizes the database rows afterwards. Receiving stops first (both MX records, then the identities SES
 * receives for), so no reply is accepted by SES with nowhere to go. Only records whose exact content UCRM would have
 * written are deleted -- anything else under these names belongs to someone else and stays. Every delete
 * treats "already gone" as done, so a retried removal is safe.
 */
export async function teardownOperationalDomain(input: {
	organizationId: string;
	rootDomain: string;
}): Promise<void> {
	const { root, sending, receiving, mailFrom } = deriveOperationalDomains(input.rootDomain);
	const { id: zoneId } = await resolveCloudflareZone(root);

	for (const name of [receiving, sending]) {
		await deleteOwnedRecords(zoneId, name, [{ type: 'MX', name, content: sesInboundMxTarget() }]);
	}

	for (const domain of [receiving, sending]) {
		// The DKIM CNAME names come from the identity's tokens, so read them before the identity is deleted.
		const identity = await getSesIdentity(domain);
		for (const record of identity ? sesDkimRecords(identity, domain) : []) {
			await deleteOwnedRecords(zoneId, record.name, [record]);
		}
		await disassociateSesTenantResource(
			sesTenantName(input.organizationId),
			sesIdentityArn(domain)
		);
		await deleteSesIdentity(domain);
	}
	await deleteOwnedRecords(zoneId, mailFrom, sesMailFromRecords(mailFrom));
}
