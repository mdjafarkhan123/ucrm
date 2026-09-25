import { Resolver } from 'node:dns/promises';
import { listCloudflareDnsRecords, resolveCloudflareZone } from './cloudflare-dns';
import {
	assertSubdomainNotOccupied,
	assertUnderSubdomain,
	EmailDomainActivationError,
	normalizeName,
	reconcileRecord
} from './dns-reconcile';
import { BREVO_INBOUND_MX_TARGETS } from './operational-domain-activation';
import { getSesIdentity, reconcileSesReceiptRule, sesInboundMxTarget } from './ses';
import {
	SES_INBOUND_BUCKET_NAME,
	SES_INBOUND_RULE_SET_NAME,
	getSesEnv,
	sesInboundTopicArn
} from './ses-env';
import {
	findExistingDomainId,
	nextLifecycleState,
	normalizeRootDomain,
	readDomainHistory,
	sesStatusToDns,
	toStoredDnsRecords,
	upsertDomainRow,
	type DnsStatus,
	type OwnerClient
} from './ses-domain-identity';

// Operational email SES Part 4: turns on customer replies for one organization's already-verified reply
// subdomain. Deliberately separate from operational-domain-activation.ts (which Raad LTD's live sending
// already runs through) so nothing here can affect an already-verified sending identity, and deliberately NOT
// wired into the existing Set-up/Check routes: this step switches a real subdomain's live MX record, so it
// runs only when explicitly invoked for one organization, never as a side effect of an unrelated Check click.
//
// Order matters (docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md): the receipt
// rule is created/updated BEFORE the MX record is written, so SES is already able to accept mail for the
// domain the moment the MX propagates. Writing the MX first would risk a window where mail addressed to SES
// has nowhere to go.

const RECEIVING_LABEL = 'reply';
const PUBLIC_DNS_SERVERS = ['1.1.1.1', '8.8.8.8'];
const MX_PRIORITY = 10;

export class ReplyIngestionNotReadyError extends EmailDomainActivationError {
	constructor(message: string) {
		super(message, 'reply_ingestion_not_ready', true);
	}
}

export type ReplyIngestionResult = {
	domain_id: string;
	domain_name: string;
	lifecycle_state: 'pending_dns' | 'verified' | 'unhealthy';
	inbound_mx_status: DnsStatus;
	records_written: number;
};

/** True when public DNS already answers the domain's MX with the SES inbound target. */
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
	return answers.flat().some((record) => normalizeName(record.exchange) === normalizeName(target));
}

/**
 * Reconciles one organization's reply subdomain: the shared receipt rule set gets (or keeps) a rule routing
 * that exact subdomain to the inbound S3 bucket and SNS topic, then the subdomain's MX is pointed at SES. Both
 * steps are idempotent, so calling this again after DNS propagates simply advances inbound_mx_status.
 *
 * Requires the reply subdomain's SES identity to already be verified (activateOperationalDomain's job) --
 * SES will not receive for a domain it has not verified, so running this earlier would write DNS for nothing.
 */
export async function activateReplyIngestion(input: {
	client: OwnerClient;
	organizationId: string;
	rootDomain: string;
}): Promise<ReplyIngestionResult> {
	const { client, organizationId } = input;
	const root = normalizeRootDomain(input.rootDomain);
	const receiving = `${RECEIVING_LABEL}.${root}`;

	const identity = await getSesIdentity(receiving);
	const identityReady =
		Boolean(identity?.dkimSigningEnabled) && sesStatusToDns(identity?.dkimStatus) === 'passing';
	if (!identity || !identityReady) {
		throw new ReplyIngestionNotReadyError(
			`${receiving} is not a verified Amazon SES identity yet. Run Set up / Check on the everyday email domain first.`
		);
	}

	const existingId = await findExistingDomainId(client, organizationId, receiving, 'receiving');
	const { id: zoneId } = await resolveCloudflareZone(root);

	const env = getSesEnv();
	await reconcileSesReceiptRule(SES_INBOUND_RULE_SET_NAME, `reply-${organizationId}`, receiving, {
		bucketName: SES_INBOUND_BUCKET_NAME,
		objectKeyPrefix: `${organizationId}/`,
		topicArn: sesInboundTopicArn(env)
	});

	const mxRecord = {
		type: 'MX' as const,
		name: receiving,
		content: sesInboundMxTarget(),
		priority: MX_PRIORITY
	};
	assertUnderSubdomain([mxRecord], receiving);
	assertSubdomainNotOccupied(receiving, await listCloudflareDnsRecords(zoneId, receiving), [
		sesInboundMxTarget(),
		...BREVO_INBOUND_MX_TARGETS
	]);
	const recordsWritten = (await reconcileRecord(zoneId, mxRecord)) === 'unchanged' ? 0 : 1;

	const mxReady = await mxIsVisible(receiving, sesInboundMxTarget());
	const inboundMxStatus: DnsStatus = mxReady ? 'passing' : 'pending';

	const now = new Date().toISOString();
	const history = await readDomainHistory(client, existingId);
	const lifecycleState = nextLifecycleState(mxReady, history);

	const domainId = await upsertDomainRow(client, existingId, {
		organization_id: organizationId,
		purpose: 'receiving',
		domain_name: receiving,
		dns_zone: root,
		provider: 'ses',
		// Receipt rules have no ARN in the classic SES API; the rule name plus the one fixed rule set name is
		// the stable handle cleanup needs to delete it.
		provider_domain_id: `reply-${organizationId}`,
		provider_verified: identityReady,
		provider_authenticated: identityReady,
		ownership_status: sesStatusToDns(identity.dkimStatus),
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
		domain_name: receiving,
		lifecycle_state: lifecycleState,
		inbound_mx_status: inboundMxStatus,
		records_written: recordsWritten
	};
}
