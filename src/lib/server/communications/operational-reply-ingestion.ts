import { Resolver } from 'node:dns/promises';
import { listCloudflareDnsRecords } from './cloudflare-dns';
import {
	assertSubdomainNotOccupied,
	assertUnderSubdomain,
	normalizeName,
	reconcileRecord
} from './dns-reconcile';
import { reconcileSesReceiptRule, sesIdentityArn, sesInboundMxTarget } from './ses';
import {
	SES_INBOUND_BUCKET_NAME,
	SES_INBOUND_OBJECT_KEY_PREFIX,
	SES_INBOUND_RULE_NAME,
	SES_INBOUND_RULE_SET_NAME,
	getSesEnv,
	sesInboundTopicArn
} from './ses-env';
import {
	nextLifecycleState,
	readDomainHistory,
	toStoredDnsRecords,
	upsertDomainRow,
	type DnsStatus,
	type OwnerClient
} from './ses-domain-identity';

// Operational email SES: the customer-replies half of Everyday email Set up / Check. Called by
// operational-domain-activation.ts once reply.<root>'s SES identity is verified -- SES will not receive for a
// domain it has not verified, so writing the MX earlier would route replies nowhere.
//
// Order matters (docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md): the receipt
// rule is created/updated BEFORE the MX record is written, so SES is already able to accept mail for the
// domain the moment the MX propagates.

const PUBLIC_DNS_SERVERS = ['1.1.1.1', '8.8.8.8'];
const MX_PRIORITY = 10;

export type ReplyIngestionResult = {
	domain_id: string;
	lifecycle_state: 'pending_dns' | 'verified' | 'unhealthy';
	inbound_mx_status: DnsStatus;
	records_written: number;
};

/**
 * True when public DNS answers the domain's MX with the SES inbound target and nothing else. Any other answer
 * still cached by a resolver means some senders would deliver elsewhere, so the route is not finished.
 */
async function mxIsVisible(domain: string, target: string): Promise<boolean> {
	// Each resolver is asked on its own, the same reasoning branded-click-domain.ts's cnameIsVisible uses: one
	// resolver can hold a stale negative answer for minutes after another already sees the record.
	const answers = await Promise.all(
		PUBLIC_DNS_SERVERS.map(async (server) => {
			const resolver = new Resolver({ timeout: 3_000, tries: 2 });
			resolver.setServers([server]);
			try {
				return await resolver.resolveMx(domain);
			} catch {
				return [];
			}
		})
	);
	const exchanges = answers.flat().map((record) => normalizeName(record.exchange));
	return exchanges.length > 0 && exchanges.every((exchange) => exchange === normalizeName(target));
}

/**
 * Reconciles one organization's reply subdomain: the account-wide receipt rule is ensured (it already receives
 * for every verified domain), then the subdomain's MX is pointed at SES. Both steps are idempotent, so the next
 * Check after DNS propagates simply advances inbound_mx_status.
 */
export async function reconcileReplyIngestion(input: {
	client: OwnerClient;
	organizationId: string;
	root: string;
	receiving: string;
	zoneId: string;
	receivingId: string | null;
}): Promise<ReplyIngestionResult> {
	const { client, organizationId, root, receiving, zoneId, receivingId } = input;

	await reconcileSesReceiptRule(SES_INBOUND_RULE_SET_NAME, SES_INBOUND_RULE_NAME, {
		bucketName: SES_INBOUND_BUCKET_NAME,
		objectKeyPrefix: SES_INBOUND_OBJECT_KEY_PREFIX,
		topicArn: sesInboundTopicArn(getSesEnv())
	});

	const mxRecord = {
		type: 'MX' as const,
		name: receiving,
		content: sesInboundMxTarget(),
		priority: MX_PRIORITY
	};
	assertUnderSubdomain([mxRecord], receiving);
	assertSubdomainNotOccupied(receiving, await listCloudflareDnsRecords(zoneId, receiving), [
		sesInboundMxTarget()
	]);
	const recordsWritten = (await reconcileRecord(zoneId, mxRecord)) === 'unchanged' ? 0 : 1;

	const mxReady = await mxIsVisible(receiving, sesInboundMxTarget());
	const inboundMxStatus: DnsStatus = mxReady ? 'passing' : 'pending';

	const now = new Date().toISOString();
	const history = await readDomainHistory(client, receivingId);
	const lifecycleState = nextLifecycleState(mxReady, history);

	const domainId = await upsertDomainRow(client, receivingId, {
		organization_id: organizationId,
		purpose: 'receiving',
		domain_name: receiving,
		dns_zone: root,
		provider: 'ses',
		// The reply identity is what makes SES receive for this domain, and it is unique per domain (the shared
		// rule is not, and provider_domain_id is unique per provider).
		provider_domain_id: sesIdentityArn(receiving),
		provider_verified: true,
		// Receiving rows never carry sending authentication (communication_email_domains_purpose_health_check).
		provider_authenticated: false,
		ownership_status: 'passing',
		dkim_status: 'unchecked',
		spf_status: 'unchecked',
		inbound_mx_status: inboundMxStatus,
		dns_records: toStoredDnsRecords([mxRecord]),
		lifecycle_state: lifecycleState,
		last_checked_at: now,
		verified_at: mxReady ? (history.verifiedAt ?? now) : history.verifiedAt,
		updated_at: now
	});

	return {
		domain_id: domainId,
		lifecycle_state: lifecycleState,
		inbound_mx_status: inboundMxStatus,
		records_written: recordsWritten
	};
}
