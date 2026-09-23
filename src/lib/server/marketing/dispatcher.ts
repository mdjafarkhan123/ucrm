import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	MarketingEmailSubmissionError,
	sendMarketingEmail,
	type MarketingEmail
} from '$lib/server/communications/ses';
import {
	runBoundedDrain,
	type BoundedDrainOptions,
	type BoundedDrainResult
} from '$lib/server/communications/drain';
import type { MarketingCampaignContent } from '$lib/marketing/campaign-content';
import { getMarketingBusinessIdentity } from '$lib/server/marketing/business-identity';
import { hydrateRuleLabels } from '$lib/server/marketing/customer-groups';
import {
	renderCampaignEmail,
	resolveMarketingVariablesPlainText,
	type MarketingBusinessIdentity
} from '$lib/server/marketing/render-email';
import {
	createMarketingCtaToken,
	resolveMarketingCtaTarget,
	withRecipientToken,
	type MarketingCtaTarget
} from '$lib/server/marketing/call-to-action';
import {
	createMarketingUnsubscribeToken,
	marketingUnsubscribeHeaders,
	marketingUnsubscribeLinkUrl
} from '$lib/server/marketing/unsubscribe-links';

// The Marketing dispatcher (M4 stage 3): claim one waiting recipient from any organization's sending
// campaign, render its frozen content, send it through the organization's own SES tenant, and finalize the
// outcome -- one recipient per call, the same competing-consumer shape as
// src/lib/server/communications/email-worker.ts, simplified because a campaign's whole audience and content
// are already frozen by marketing_launch_campaign. See Memory/campaigns/marketing-growth/parts/M4.md for the
// stage's approved decisions.

type ClaimedMarketingRecipient = {
	recipient_id: string;
	campaign_id: string;
	organization_id: string;
	claim_token: string;
	client_id: string;
	client_contact_method_id: string;
	recipient_email: string;
	display_name: string;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type MarketingWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

type WorkerDependencies = {
	client?: MarketingWorkerClient;
	send?: (message: MarketingEmail) => Promise<{ messageId: string }>;
	// Injectable like email-worker.ts's readAttachment: the real implementation reaches the database
	// directly (context loading is several unrelated table reads, not one RPC a fake client.rpc could
	// stand in for), so tests substitute a fixed context instead of faking a Supabase query builder.
	loadContext?: (organizationId: string, campaignId: string) => Promise<CampaignSendContext>;
};

// One claim/send/finalize attempt. 'idle' means the queue held no claimable row; otherwise the finalized
// provider outcome for the single recipient this call processed.
export type ProcessedMarketingResult =
	| { status: 'idle' }
	| {
			status: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
			recipientId: string;
	  };

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: MarketingWorkerClient): MarketingWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as MarketingWorkerClient);
}

// Releases abandoned claims from a prior wake back into submission_unknown. Runs once per drain, before any
// slot claims, same as quarantineStaleEmailClaims.
export async function quarantineStaleMarketingClaims(
	client: MarketingWorkerClient
): Promise<number> {
	const quarantine = await client.rpc('quarantine_stale_marketing_campaign_claims', {
		batch_size: 50,
		stale_after: '15 minutes'
	});
	if (quarantine.error)
		throw rpcError('Could not quarantine stale marketing claims', quarantine.error);
	return typeof quarantine.data === 'number' ? quarantine.data : 0;
}

export type OrganizationMarketingSendContext = {
	business: MarketingBusinessIdentity;
	fromEmail: string;
	fromName: string;
	senderId: string;
	// The organization-wide Reply-To, used only when the customer's own reply alias cannot be made (no verified
	// receiving domain). A real send prefers the alias so the reply lands in that customer's conversation.
	replyTo: { email: string; name: string };
	// Verified receiving domains by id, so a reply alias row becomes an address without another query.
	receivingDomains: Record<string, string>;
	tenantName: string;
	configurationSetName: string;
};

// Everything a Marketing send needs from the organization itself, independent of any one campaign's content:
// the real per-org SES tenant, the verified news.<root> identity, and the derived From address (stage 3's
// decision). Shared by the dispatcher below (which adds a launched campaign's frozen content) and the
// test-send path (which sends arbitrary in-editor content through this same real identity, stage 5 -- see
// Memory/campaigns/marketing-growth/parts/M4.md).
export async function buildOrganizationMarketingSendContext(
	organizationId: string
): Promise<OrganizationMarketingSendContext> {
	const owner = getOwnerSupabaseClient();

	const [organization, marketingDomain, sendingDomains, tenant, receivingDomains] =
		await Promise.all([
			owner.from('organizations').select('name').eq('id', organizationId).single(),
			// The verified news.<root> identity a send actually leaves from -- claim_marketing_campaign_recipient
			// only claims a recipient once this exists, so a missing row here means the identity dropped out from
			// under an already-claimed recipient.
			owner
				.from('communication_email_domains')
				.select('domain_name')
				.eq('organization_id', organizationId)
				.eq('purpose', 'marketing_sending')
				.eq('lifecycle_state', 'verified')
				.single(),
			owner
				.from('communication_email_domains')
				.select('id')
				.eq('organization_id', organizationId)
				.eq('purpose', 'sending')
				.eq('lifecycle_state', 'verified')
				.eq('provider_verified', true)
				.eq('provider_authenticated', true)
				.eq('ownership_status', 'passing')
				.eq('dkim_status', 'passing'),
			owner
				.from('communication_ses_tenants')
				.select('tenant_name, configuration_set_name')
				.eq('organization_id', organizationId)
				.single(),
			owner
				.from('communication_email_domains')
				.select('id, domain_name')
				.eq('organization_id', organizationId)
				.eq('purpose', 'receiving')
				.eq('lifecycle_state', 'verified')
		]);

	for (const result of [organization, marketingDomain, sendingDomains, tenant, receivingDomains]) {
		if (result.error) throw result.error;
	}
	// .single() already errored above when a row was missing, so a null .data here is unreachable -- these
	// checks only narrow the type.
	if (!organization.data || !marketingDomain.data || !tenant.data)
		throw new Error('A required Marketing send record could not be read.');

	const sendingDomainIds = (sendingDomains.data ?? []).map((domain) => domain.id);
	if (sendingDomainIds.length === 0)
		throw new Error('The organization has no verified operational sending domain.');

	// The operational sender the Marketing From address derives its display name and local part from --
	// same eligible-sender query as readiness.ts and delivery-options.ts.
	const { data: senderRow, error: senderError } = await owner
		.from('communication_email_senders')
		.select('id, email_address, display_name')
		.eq('organization_id', organizationId)
		.eq('lifecycle_state', 'enabled')
		.in('domain_id', sendingDomainIds)
		.order('is_organization_default', { ascending: false })
		.order('created_at')
		.limit(1)
		.maybeSingle();
	if (senderError) throw senderError;
	if (!senderRow) throw new Error('The organization has no enabled sender.');

	const business = await getMarketingBusinessIdentity(organizationId, organization.data.name);
	const localPart = senderRow.email_address.split('@')[0];

	return {
		business,
		fromEmail: `${localPart}@${marketingDomain.data.domain_name}`,
		fromName: senderRow.display_name,
		senderId: senderRow.id,
		replyTo: { email: senderRow.email_address, name: senderRow.display_name },
		receivingDomains: Object.fromEntries(
			(receivingDomains.data ?? []).map((domain) => [domain.id, domain.domain_name])
		),
		tenantName: tenant.data.tenant_name,
		configurationSetName: tenant.data.configuration_set_name
	};
}

export type CampaignSendContext = OrganizationMarketingSendContext & {
	content: MarketingCampaignContent;
	serviceNames: Record<string, string>;
	// Resolved once per campaign; each recipient's form link then gets its own token.
	cta: MarketingCtaTarget | null;
};

export function appOrigin(): string {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin) throw new Error('APP_URL must be set before Marketing email can send.');
	return new URL(rawOrigin).origin;
}

// A launched campaign's content, sender identity, and tenant never change again, so this is built at most
// once per campaign per worker process and reused for every recipient. Caching the in-flight promise (not
// just its result) means two concurrent drain slots claiming the same campaign's recipients share one build
// instead of racing two. A failed build is evicted so the next attempt retries rather than repeating the
// same error forever.
const campaignContextCache = new Map<string, Promise<CampaignSendContext>>();

async function buildCampaignSendContext(
	organizationId: string,
	campaignId: string
): Promise<CampaignSendContext> {
	const owner = getOwnerSupabaseClient();

	const [campaign, orgContext] = await Promise.all([
		owner
			.from('marketing_campaigns')
			.select('content')
			.eq('id', campaignId)
			.eq('organization_id', organizationId)
			.single(),
		buildOrganizationMarketingSendContext(organizationId)
	]);

	if (campaign.error) throw campaign.error;
	// .single() already errored above when the row was missing, so a null .data here is unreachable -- this
	// check only narrows the type.
	if (!campaign.data) throw new Error('A required Marketing send record could not be read.');

	const content = campaign.data.content as unknown as MarketingCampaignContent;
	const catalogItemIds = content.blocks
		.filter((block) => block.type === 'service_summary')
		.flatMap((block) => (block.type === 'service_summary' ? block.catalog_item_ids : []));

	const [labels, cta] = await Promise.all([
		hydrateRuleLabels(organizationId, catalogItemIds, []),
		resolveMarketingCtaTarget(organizationId, content.cta, appOrigin())
	]);
	const serviceNames = Object.fromEntries(
		labels.catalog_items.map((item) => [item.id, item.label])
	);

	return { content, serviceNames, cta, ...orgContext };
}

function loadCampaignSendContext(
	organizationId: string,
	campaignId: string
): Promise<CampaignSendContext> {
	const cached = campaignContextCache.get(campaignId);
	if (cached) return cached;
	const built = buildCampaignSendContext(organizationId, campaignId);
	built.catch(() => campaignContextCache.delete(campaignId));
	campaignContextCache.set(campaignId, built);
	return built;
}

// customer_first_name has no name-parsing library behind it: the first whitespace token of the recipient's
// stored display name, exactly as decided in Memory/campaigns/marketing-growth/parts/M4.md.
function firstNameToken(displayName: string): string {
	return displayName.trim().split(/\s+/)[0] ?? displayName;
}

export async function processClaimedMarketingRecipient(
	dependencies: WorkerDependencies = {}
): Promise<ProcessedMarketingResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendMarketingEmail;
	const loadContext = dependencies.loadContext ?? loadCampaignSendContext;

	const claimed = await client.rpc('claim_marketing_campaign_recipient');
	if (claimed.error)
		throw rpcError('Could not claim a marketing campaign recipient', claimed.error);
	const recipient = Array.isArray(claimed.data)
		? (claimed.data[0] as ClaimedMarketingRecipient | undefined)
		: undefined;
	if (!recipient) return { status: 'idle' };

	let outcome: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
	let providerMessageId: string | undefined;
	let failureCode: string | undefined;
	let failureMessage: string | undefined;

	try {
		const context = await loadContext(recipient.organization_id, recipient.campaign_id);

		const origin = appOrigin();

		const { token, tokenHash } = createMarketingUnsubscribeToken();
		const issued = await client.rpc('issue_client_marketing_unsubscribe_link', {
			target_organization_id: recipient.organization_id,
			target_client_contact_method_id: recipient.client_contact_method_id,
			supplied_token_hash: tokenHash,
			target_marketing_campaign_recipient_id: recipient.recipient_id
		});
		if (issued.error) throw rpcError('Could not issue a marketing unsubscribe link', issued.error);

		let cta = context.cta;
		if (cta?.type === 'internal_form') {
			const ctaToken = createMarketingCtaToken();
			const ctaIssued = await client.rpc('issue_marketing_campaign_cta_link', {
				target_recipient_id: recipient.recipient_id,
				target_claim_token: recipient.claim_token,
				supplied_token_hash: ctaToken.tokenHash
			});
			if (ctaIssued.error)
				throw rpcError('Could not issue a marketing call-to-action link', ctaIssued.error);
			cta = withRecipientToken(cta, ctaToken.token);
		}

		// The same per-customer alias operational email uses, so a reply lands in this customer's own
		// conversation; the inbound trigger then tags it with the campaign from In-Reply-To.
		const aliased = await client.rpc('ensure_communication_reply_alias', {
			target_organization_id: recipient.organization_id,
			target_sender_id: context.senderId,
			target_client_id: recipient.client_id,
			target_contact_method_id: recipient.client_contact_method_id
		});
		if (aliased.error) throw rpcError('Could not prepare a reply address', aliased.error);
		const alias = aliased.data as {
			alias_local_part: string | null;
			receiving_domain_id: string | null;
		} | null;
		const aliasDomain = alias?.receiving_domain_id
			? context.receivingDomains[alias.receiving_domain_id]
			: undefined;
		const replyTo =
			alias?.alias_local_part && aliasDomain
				? { email: `${alias.alias_local_part}@${aliasDomain}`, name: context.replyTo.name }
				: context.replyTo;

		const variables = {
			customer_first_name: firstNameToken(recipient.display_name),
			business_name: context.business.name
		};

		const rendered = await renderCampaignEmail(context.content, {
			variables,
			serviceNames: context.serviceNames,
			business: context.business,
			unsubscribeUrl: marketingUnsubscribeLinkUrl(origin, token),
			cta
		});
		if (rendered.errors.length > 0)
			throw new MarketingEmailSubmissionError(
				`The campaign content could not be rendered: ${rendered.errors[0]?.message ?? 'unknown MJML error'}.`,
				'cancelled',
				'marketing_render_invalid'
			);

		const headers = marketingUnsubscribeHeaders(origin, token);
		const submitted = await send({
			from: { email: context.fromEmail, name: context.fromName },
			to: { email: recipient.recipient_email },
			replyTo,
			subject: resolveMarketingVariablesPlainText(context.content.subject, variables),
			htmlContent: rendered.html,
			textContent: rendered.text,
			tenantName: context.tenantName,
			configurationSetName: context.configurationSetName,
			headers: Object.entries(headers).map(([name, value]) => ({ name, value }))
		});
		outcome = 'submitted';
		providerMessageId = submitted.messageId;
	} catch (error) {
		if (error instanceof MarketingEmailSubmissionError) {
			outcome = error.outcome;
			failureCode = error.code;
			failureMessage = error.message;
		} else {
			outcome = 'submission_unknown';
			failureCode = 'worker_submission_unknown';
			failureMessage = 'The worker could not determine the provider submission outcome.';
		}
	}

	const finalized = await client.rpc('finalize_marketing_campaign_send', {
		target_recipient_id: recipient.recipient_id,
		target_claim_token: recipient.claim_token,
		target_outcome: outcome,
		target_provider_message_id: providerMessageId,
		target_failure_code: failureCode,
		target_failure_message: failureMessage
	});
	if (finalized.error)
		throw rpcError('Could not finalize a marketing campaign send', finalized.error);

	return { status: outcome, recipientId: recipient.recipient_id };
}

// Wakes the marketing outbox: quarantine once, then bounded concurrent claim/send/finalize until the queue
// is idle, the claim cap is reached, or the time budget expires.
export async function drainMarketingCampaignQueue(
	dependencies: WorkerDependencies & BoundedDrainOptions = {}
): Promise<BoundedDrainResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendMarketingEmail;
	const loadContext = dependencies.loadContext ?? loadCampaignSendContext;

	return runBoundedDrain(
		() => quarantineStaleMarketingClaims(client),
		() => processClaimedMarketingRecipient({ client, send, loadContext }),
		dependencies
	);
}

// Stable identity for the marketing outbox worker's lease and ledger rows. Must match the worker_name the
// Cron dispatch function (dispatch_communication_marketing_worker_wake) and the health read use.
export const MARKETING_WORKER_NAME = 'communications-marketing-outbox';
const LEASE_TTL_SECONDS = 55;
const ROUTE_DEADLINE_MS = 40_000;

export type MarketingWakeOutcome =
	BoundedDrainResult['stoppedBy'] | 'already_running' | 'route_deadline' | 'error';

export type MonitoredMarketingWakeResult = {
	outcome: MarketingWakeOutcome;
} & Partial<BoundedDrainResult>;

type MonitoredWakeDependencies = WorkerDependencies &
	BoundedDrainOptions & {
		wakeCorrelationId: string;
		leaseTtlSeconds?: number;
		routeDeadlineMs?: number;
		nowIso?: () => string;
	};

// The ledger is best-effort monitoring, never the correctness boundary -- same trade as
// recordEmailWakeResult.
async function recordMarketingWakeResult(
	client: MarketingWorkerClient,
	args: {
		wakeCorrelationId: string;
		startedAt: string;
		finishedAt: string;
		outcome: MarketingWakeOutcome;
		result?: BoundedDrainResult;
	}
): Promise<void> {
	const { result } = args;
	const record = await client.rpc('record_communication_worker_wake_result', {
		p_worker_name: MARKETING_WORKER_NAME,
		p_wake_correlation_id: args.wakeCorrelationId,
		p_started_at: args.startedAt,
		p_finished_at: args.finishedAt,
		p_route_outcome: args.outcome,
		p_stale_claims_quarantined: result?.staleClaimsQuarantined ?? null,
		p_claimed: result?.claimed ?? null,
		p_submitted: result?.submitted ?? null,
		p_retried: result?.retried ?? null,
		p_cancelled: result?.cancelled ?? null,
		p_submission_unknown: result?.submissionUnknown ?? null
	});
	if (record.error)
		console.error('Could not record the marketing worker wake result.', record.error);
}

// One monitored wake, mirroring runMonitoredEmailWake exactly: single-flight lease, bounded drain under a
// hard route deadline, attributable ledger write, lease release. A deadline trip leaves the lease to expire
// on its own so the still-running drain keeps its claim ownership.
export async function runMonitoredMarketingWake(
	dependencies: MonitoredWakeDependencies
): Promise<MonitoredMarketingWakeResult> {
	const client = resolveClient(dependencies.client);
	const nowIso = dependencies.nowIso ?? (() => new Date().toISOString());
	const startedAt = nowIso();

	const acquired = await client.rpc('acquire_communication_worker_lease', {
		p_worker_name: MARKETING_WORKER_NAME,
		p_ttl_seconds: dependencies.leaseTtlSeconds ?? LEASE_TTL_SECONDS
	});
	if (acquired.error)
		throw rpcError('Could not acquire the marketing worker lease', acquired.error);
	const leaseToken = typeof acquired.data === 'string' ? acquired.data : null;

	if (!leaseToken) {
		await recordMarketingWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'already_running'
		});
		return { outcome: 'already_running' };
	}

	const deadlineMs = dependencies.routeDeadlineMs ?? ROUTE_DEADLINE_MS;
	let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
	const drain = drainMarketingCampaignQueue({ ...dependencies, client });

	try {
		const raced = await Promise.race([
			drain.then((result) => ({ kind: 'done' as const, result })),
			new Promise<{ kind: 'deadline' }>((resolve) => {
				deadlineTimer = setTimeout(() => resolve({ kind: 'deadline' }), deadlineMs);
			})
		]);

		if (raced.kind === 'deadline') {
			drain.catch(() => {});
			await recordMarketingWakeResult(client, {
				wakeCorrelationId: dependencies.wakeCorrelationId,
				startedAt,
				finishedAt: nowIso(),
				outcome: 'route_deadline'
			});
			return { outcome: 'route_deadline' };
		}

		await releaseMarketingWakeLease(client, leaseToken);
		await recordMarketingWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: raced.result.stoppedBy,
			result: raced.result
		});
		return { outcome: raced.result.stoppedBy, ...raced.result };
	} catch (error) {
		await releaseMarketingWakeLease(client, leaseToken);
		await recordMarketingWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'error'
		});
		throw error;
	} finally {
		if (deadlineTimer) clearTimeout(deadlineTimer);
	}
}

async function releaseMarketingWakeLease(
	client: MarketingWorkerClient,
	leaseToken: string
): Promise<void> {
	const released = await client.rpc('release_communication_worker_lease', {
		p_worker_name: MARKETING_WORKER_NAME,
		p_lease_token: leaseToken
	});
	if (released.error)
		console.error('Could not release the marketing worker lease.', released.error);
}
