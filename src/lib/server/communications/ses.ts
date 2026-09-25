import {
	SESv2Client,
	CreateConfigurationSetCommand,
	CreateConfigurationSetEventDestinationCommand,
	CreateEmailIdentityCommand,
	CreateTenantCommand,
	CreateTenantResourceAssociationCommand,
	DeleteConfigurationSetCommand,
	DeleteEmailIdentityCommand,
	DeleteTenantCommand,
	GetConfigurationSetCommand,
	GetConfigurationSetEventDestinationsCommand,
	GetEmailIdentityCommand,
	GetTenantCommand,
	ListTenantResourcesCommand,
	PutConfigurationSetTrackingOptionsCommand,
	PutEmailIdentityMailFromAttributesCommand,
	SendEmailCommand,
	UpdateConfigurationSetEventDestinationCommand,
	type EventType
} from '@aws-sdk/client-sesv2';
import {
	SESClient,
	CreateReceiptRuleCommand,
	DeleteReceiptRuleCommand,
	DescribeReceiptRuleCommand,
	UpdateReceiptRuleCommand,
	type ReceiptRule
} from '@aws-sdk/client-ses';
import MailComposer from 'nodemailer/lib/mail-composer';
import { getSesEnv, SesError } from './ses-env';

// Server-only Amazon SES v2 adapter. Like cloudflare-dns.ts, it exposes thin, idempotent primitives and
// NOTHING about which resources an organization should have: the Marketing identity reconciler owns that
// policy. Credentials never enter a browser response.
//
// Every "get" returns null when the resource does not exist, so a caller reconciles by reading first and
// creating only what is missing. A create that races another caller surfaces as already-exists, which the
// reconciler treats as success rather than a failure.

const SES_REQUEST_TIMEOUT_MS = 10_000;

// The seven delivery event types the provisioned SNS -> SQS pipeline was proven against, plus OPEN and CLICK
// (M5a, Jafar-approved): subscribing a configuration set to them is what makes SES add its open pixel and
// rewrite links for click tracking. Results show opens as directional only. SUBSCRIPTION stays absent --
// unsubscribe is UCRM-owned. Named SES_EVENT_TYPES, not MARKETING_EVENT_TYPES, because
// ensureSesEventDestination is provider-agnostic and now serves both the Marketing and the operational
// configuration set.
const SES_EVENT_TYPES: EventType[] = [
	'SEND',
	'DELIVERY',
	'BOUNCE',
	'COMPLAINT',
	'REJECT',
	'DELIVERY_DELAY',
	'RENDERING_FAILURE',
	'OPEN',
	'CLICK'
];

const EVENT_DESTINATION_NAME = 'sns-all-events';

let cached: { client: SESv2Client; env: ReturnType<typeof getSesEnv> } | null = null;

function getSes(): { client: SESv2Client; env: ReturnType<typeof getSesEnv> } {
	if (cached) return cached;
	const env = getSesEnv();
	const client = new SESv2Client({
		region: env.AWS_SES_REGION,
		credentials: {
			accessKeyId: env.AWS_SES_ACCESS_KEY_ID,
			secretAccessKey: env.AWS_SES_SECRET_ACCESS_KEY
		},
		requestHandler: { requestTimeout: SES_REQUEST_TIMEOUT_MS, connectionTimeout: 5_000 }
	});
	cached = { client, env };
	return cached;
}

// Receipt rules (customer replies) have no SESv2 equivalent -- only the classic SES API manages them -- so
// this is a second, separately cached client against the same credentials and region.
let cachedV1: { client: SESClient; env: ReturnType<typeof getSesEnv> } | null = null;

function getSesV1(): { client: SESClient; env: ReturnType<typeof getSesEnv> } {
	if (cachedV1) return cachedV1;
	const env = getSesEnv();
	const client = new SESClient({
		region: env.AWS_SES_REGION,
		credentials: {
			accessKeyId: env.AWS_SES_ACCESS_KEY_ID,
			secretAccessKey: env.AWS_SES_SECRET_ACCESS_KEY
		},
		requestHandler: { requestTimeout: SES_REQUEST_TIMEOUT_MS, connectionTimeout: 5_000 }
	});
	cachedV1 = { client, env };
	return cachedV1;
}

type AwsError = { name?: string; message?: string; $metadata?: { httpStatusCode?: number } };

function sesStatus(error: unknown): number | null {
	return (error as AwsError)?.$metadata?.httpStatusCode ?? null;
}

function isNotFound(error: unknown): boolean {
	return (error as AwsError)?.name === 'NotFoundException' || sesStatus(error) === 404;
}

function isAlreadyExists(error: unknown): boolean {
	return (error as AwsError)?.name === 'AlreadyExistsException' || sesStatus(error) === 409;
}

/**
 * Turns an SDK error into a SesError carrying an HTTP status. A network failure or timeout has no status,
 * which the reconciler reads as an ambiguous outcome it re-derives rather than a proven failure -- the same
 * contract cloudflare-dns.ts and brevo.ts use.
 */
function toSesError(operation: string, error: unknown): SesError {
	const status = sesStatus(error);
	const detail = (error as AwsError)?.message;
	return new SesError(
		`Amazon SES rejected ${operation}${detail ? `: ${detail}` : '.'}`,
		status,
		status == null ? 'ses_network_unknown' : `ses_${(error as AwsError)?.name ?? status}`
	);
}

async function sesCall<T>(operation: string, run: () => Promise<T>): Promise<T> {
	try {
		return await run();
	} catch (error) {
		throw toSesError(operation, error);
	}
}

export type SesIdentity = {
	verifiedForSending: boolean;
	dkimStatus: string | null;
	dkimSigningEnabled: boolean;
	dkimTokens: string[];
	mailFromDomain: string | null;
	mailFromStatus: string | null;
};

export async function getSesIdentity(domain: string): Promise<SesIdentity | null> {
	const { client } = getSes();
	try {
		const result = await client.send(new GetEmailIdentityCommand({ EmailIdentity: domain }));
		return {
			verifiedForSending: result.VerifiedForSendingStatus ?? false,
			dkimStatus: result.DkimAttributes?.Status ?? null,
			dkimSigningEnabled: result.DkimAttributes?.SigningEnabled ?? false,
			dkimTokens: result.DkimAttributes?.Tokens ?? [],
			mailFromDomain: result.MailFromAttributes?.MailFromDomain ?? null,
			mailFromStatus: result.MailFromAttributes?.MailFromDomainStatus ?? null
		};
	} catch (error) {
		if (isNotFound(error)) return null;
		throw toSesError('GetEmailIdentity', error);
	}
}

/** Creates a domain identity with Easy DKIM, so SES owns the key material and publishes three CNAME tokens. */
export async function createSesIdentity(domain: string): Promise<void> {
	const { client } = getSes();
	try {
		await client.send(
			new CreateEmailIdentityCommand({
				EmailIdentity: domain,
				// SES now refuses AWS_SES-origin signing without an explicit key length (verified 2026-09-25:
				// "Invalid identity configuration"). 2048-bit is the strongest Easy DKIM key and what the
				// existing identities already use.
				DkimSigningAttributes: {
					DomainSigningAttributesOrigin: 'AWS_SES',
					NextSigningKeyLength: 'RSA_2048_BIT'
				}
			})
		);
	} catch (error) {
		if (isAlreadyExists(error)) return;
		throw toSesError('CreateEmailIdentity', error);
	}
}

/**
 * Points the identity at a custom MAIL FROM subdomain. USE_DEFAULT_VALUE means a MAIL FROM whose DNS has not
 * propagated yet falls back to amazonses.com instead of rejecting the message -- mail keeps flowing while the
 * records settle, and SPF alignment starts the moment they resolve.
 */
export async function putSesIdentityMailFrom(
	domain: string,
	mailFromDomain: string
): Promise<void> {
	const { client } = getSes();
	await sesCall('PutEmailIdentityMailFromAttributes', () =>
		client.send(
			new PutEmailIdentityMailFromAttributesCommand({
				EmailIdentity: domain,
				MailFromDomain: mailFromDomain,
				BehaviorOnMxFailure: 'USE_DEFAULT_VALUE'
			})
		)
	);
}

export async function getSesTenant(
	tenantName: string
): Promise<{ tenantArn: string | null } | null> {
	const { client } = getSes();
	try {
		const result = await client.send(new GetTenantCommand({ TenantName: tenantName }));
		return { tenantArn: result.Tenant?.TenantArn ?? null };
	} catch (error) {
		if (isNotFound(error)) return null;
		throw toSesError('GetTenant', error);
	}
}

export async function createSesTenant(tenantName: string): Promise<{ tenantArn: string | null }> {
	const { client } = getSes();
	try {
		const result = await client.send(new CreateTenantCommand({ TenantName: tenantName }));
		return { tenantArn: result.TenantArn ?? null };
	} catch (error) {
		if (isAlreadyExists(error)) return (await getSesTenant(tenantName)) ?? { tenantArn: null };
		throw toSesError('CreateTenant', error);
	}
}

/** Every identity and configuration set associated with a tenant, as ARNs, across all pages. */
export async function listSesTenantResources(
	tenantName: string
): Promise<{ type: string; arn: string }[]> {
	const { client } = getSes();
	const resources: { type: string; arn: string }[] = [];
	let nextToken: string | undefined;
	do {
		let page;
		try {
			page = await client.send(
				new ListTenantResourcesCommand({ TenantName: tenantName, NextToken: nextToken })
			);
		} catch (error) {
			if (isNotFound(error)) return [];
			throw toSesError('ListTenantResources', error);
		}
		for (const resource of page.TenantResources ?? []) {
			if (resource.ResourceType && resource.ResourceArn)
				resources.push({ type: resource.ResourceType, arn: resource.ResourceArn });
		}
		nextToken = page.NextToken;
	} while (nextToken);
	return resources;
}

/** Deletes a tenant. Already-gone is the desired state, so a retried cleanup is safe. */
export async function deleteSesTenant(tenantName: string): Promise<void> {
	const { client } = getSes();
	try {
		await client.send(new DeleteTenantCommand({ TenantName: tenantName }));
	} catch (error) {
		if (isNotFound(error)) return;
		throw toSesError('DeleteTenant', error);
	}
}

export async function configurationSetExists(configurationSetName: string): Promise<boolean> {
	const { client } = getSes();
	try {
		await client.send(
			new GetConfigurationSetCommand({ ConfigurationSetName: configurationSetName })
		);
		return true;
	} catch (error) {
		if (isNotFound(error)) return false;
		throw toSesError('GetConfigurationSet', error);
	}
}

export async function createSesConfigurationSet(configurationSetName: string): Promise<void> {
	const { client } = getSes();
	try {
		await client.send(
			new CreateConfigurationSetCommand({ ConfigurationSetName: configurationSetName })
		);
	} catch (error) {
		if (isAlreadyExists(error)) return;
		throw toSesError('CreateConfigurationSet', error);
	}
}

/** Deletes a configuration set. Already-gone is the desired state, so a retried cleanup is safe. */
export async function deleteSesConfigurationSet(configurationSetName: string): Promise<void> {
	const { client } = getSes();
	try {
		await client.send(
			new DeleteConfigurationSetCommand({ ConfigurationSetName: configurationSetName })
		);
	} catch (error) {
		if (isNotFound(error)) return;
		throw toSesError('DeleteConfigurationSet', error);
	}
}

/**
 * Attaches the shared SNS topic to this configuration set so its delivery events reach the one SQS queue the
 * event consumer drains. Returns true once the destination is in place, whether this call created it or an
 * earlier run did.
 */
export async function ensureSesEventDestination(configurationSetName: string): Promise<boolean> {
	const { client, env } = getSes();
	const existing = await sesCall('GetConfigurationSetEventDestinations', () =>
		client.send(
			new GetConfigurationSetEventDestinationsCommand({
				ConfigurationSetName: configurationSetName
			})
		)
	);
	const attached = (existing.EventDestinations ?? []).find(
		(destination) => destination.SnsDestination?.TopicArn === env.AWS_SES_EVENT_SNS_TOPIC_ARN
	);
	if (attached) {
		// A destination created before OPEN/CLICK were added is widened in place, so re-running activation
		// upgrades an organization that already sends.
		const current = new Set(attached.MatchingEventTypes ?? []);
		if (SES_EVENT_TYPES.every((type) => current.has(type)) && attached.Enabled) return true;
		await sesCall('UpdateConfigurationSetEventDestination', () =>
			client.send(
				new UpdateConfigurationSetEventDestinationCommand({
					ConfigurationSetName: configurationSetName,
					EventDestinationName: attached.Name,
					EventDestination: {
						Enabled: true,
						MatchingEventTypes: SES_EVENT_TYPES,
						SnsDestination: { TopicArn: env.AWS_SES_EVENT_SNS_TOPIC_ARN }
					}
				})
			)
		);
		return true;
	}

	try {
		await client.send(
			new CreateConfigurationSetEventDestinationCommand({
				ConfigurationSetName: configurationSetName,
				EventDestinationName: EVENT_DESTINATION_NAME,
				EventDestination: {
					Enabled: true,
					MatchingEventTypes: SES_EVENT_TYPES,
					SnsDestination: { TopicArn: env.AWS_SES_EVENT_SNS_TOPIC_ARN }
				}
			})
		);
		return true;
	} catch (error) {
		if (isAlreadyExists(error)) return true;
		throw toSesError('CreateConfigurationSetEventDestination', error);
	}
}

/**
 * Deletes a domain identity. An identity that is already gone is the desired state, so a retried removal is
 * safe. Deleting the identity also ends every tenant association that pointed at it.
 */
export async function deleteSesIdentity(domain: string): Promise<void> {
	const { client } = getSes();
	try {
		await client.send(new DeleteEmailIdentityCommand({ EmailIdentity: domain }));
	} catch (error) {
		if (isNotFound(error)) return;
		throw toSesError('DeleteEmailIdentity', error);
	}
}

/**
 * Authorizes a tenant to use one identity or configuration set. A tenant with neither cannot send at all, so
 * both associations are required before the dispatcher's first send.
 */
export async function associateSesTenantResource(
	tenantName: string,
	resourceArn: string
): Promise<void> {
	const { client } = getSes();
	try {
		await client.send(
			new CreateTenantResourceAssociationCommand({
				TenantName: tenantName,
				ResourceArn: resourceArn
			})
		);
	} catch (error) {
		if (isAlreadyExists(error)) return;
		throw toSesError('CreateTenantResourceAssociation', error);
	}
}

/**
 * The branded click-tracking domain the configuration set currently rewrites links onto, or null when it uses
 * Amazon's default tracking host.
 */
export async function getSesClickTrackingDomain(
	configurationSetName: string
): Promise<string | null> {
	const { client } = getSes();
	const result = await sesCall('GetConfigurationSet', () =>
		client.send(new GetConfigurationSetCommand({ ConfigurationSetName: configurationSetName }))
	);
	return result.TrackingOptions?.CustomRedirectDomain?.toLowerCase() ?? null;
}

/**
 * Points open and click tracking at a branded domain, or back at Amazon's default host when `domain` is null.
 * REQUIRE keeps every rewritten link on HTTPS; SES refuses a domain it cannot inherit verification for, which
 * click.news.<root> gets from the verified news.<root> identity.
 */
export async function putSesClickTrackingDomain(
	configurationSetName: string,
	domain: string | null
): Promise<void> {
	const { client } = getSes();
	await sesCall('PutConfigurationSetTrackingOptions', () =>
		client.send(
			new PutConfigurationSetTrackingOptionsCommand({
				ConfigurationSetName: configurationSetName,
				...(domain ? { CustomRedirectDomain: domain, HttpsPolicy: 'REQUIRE' as const } : {})
			})
		)
	);
}

export function sesIdentityArn(domain: string): string {
	const { env } = getSes();
	return `arn:aws:ses:${env.AWS_SES_REGION}:${env.accountId}:identity/${domain}`;
}

export function sesConfigurationSetArn(configurationSetName: string): string {
	const { env } = getSes();
	return `arn:aws:ses:${env.AWS_SES_REGION}:${env.accountId}:configuration-set/${configurationSetName}`;
}

/**
 * The region-specific host that receives mail for an SES receiving domain. Customer replies only move to it once
 * a receipt rule for the domain exists; until then a reply subdomain keeps its current MX.
 */
export function sesInboundMxTarget(): string {
	const { env } = getSes();
	return `inbound-smtp.${env.AWS_SES_REGION}.amazonaws.com`;
}

/** The region-specific host a custom MAIL FROM subdomain must point its MX record at. */
export function sesMailFromMxTarget(): string {
	const { env } = getSes();
	return `feedback-smtp.${env.AWS_SES_REGION}.amazonses.com`;
}

// ---------------------------------------------------------------------------------------------------
// Marketing send (M4 stage 3). Mirrors OperationalEmailSubmissionError's three-way outcome from brevo.ts:
// 'retry' for a transient rejection worth trying again, 'cancelled' for one that will never succeed, and
// 'submission_unknown' when the SDK call itself never returned an answer (a request that reached SES may
// have already been accepted, so a blind retry risks a duplicate send to a real customer).
// ---------------------------------------------------------------------------------------------------

export class MarketingEmailSubmissionError extends Error {
	constructor(
		message: string,
		public readonly outcome: 'retry' | 'cancelled' | 'submission_unknown',
		public readonly code: string
	) {
		super(message);
		this.name = 'MarketingEmailSubmissionError';
	}
}

export type MarketingEmail = {
	from: { email: string; name: string };
	to: { email: string };
	replyTo: { email: string; name: string };
	subject: string;
	htmlContent: string;
	textContent: string;
	tenantName: string;
	configurationSetName: string;
	// RFC 8058 List-Unsubscribe / List-Unsubscribe-Post, built by unsubscribe-links.ts.
	headers: { name: string; value: string }[];
};

function formattedAddress(address: { email: string; name?: string }): string {
	return address.name ? `${address.name} <${address.email}>` : address.email;
}

export async function sendMarketingEmail(message: MarketingEmail): Promise<{ messageId: string }> {
	const { client } = getSes();
	try {
		const result = await client.send(
			new SendEmailCommand({
				FromEmailAddress: formattedAddress(message.from),
				Destination: { ToAddresses: [message.to.email] },
				ReplyToAddresses: [formattedAddress(message.replyTo)],
				Content: {
					Simple: {
						Subject: { Data: message.subject, Charset: 'UTF-8' },
						Body: {
							Html: { Data: message.htmlContent, Charset: 'UTF-8' },
							Text: { Data: message.textContent, Charset: 'UTF-8' }
						},
						Headers: message.headers.map((header) => ({
							Name: header.name,
							Value: header.value
						}))
					}
				},
				ConfigurationSetName: message.configurationSetName,
				TenantName: message.tenantName
			})
		);

		if (!result.MessageId)
			throw new MarketingEmailSubmissionError(
				'Amazon SES accepted the request without returning a message identifier.',
				'submission_unknown',
				'ses_missing_message_id'
			);
		return { messageId: result.MessageId };
	} catch (error) {
		if (error instanceof MarketingEmailSubmissionError) throw error;
		const status = sesStatus(error);
		const retryable = status === 429 || (status !== null && status >= 500);
		throw new MarketingEmailSubmissionError(
			`Amazon SES rejected the send${(error as AwsError)?.message ? `: ${(error as AwsError).message}` : '.'}`,
			status == null ? 'submission_unknown' : retryable ? 'retry' : 'cancelled',
			status == null ? 'ses_network_unknown' : `ses_${(error as AwsError)?.name ?? status}`
		);
	}
}

// ---------------------------------------------------------------------------------------------------
// Operational send (Part 3). Same three-way outcome contract as OperationalEmailSubmissionError (brevo.ts),
// but built as a raw MIME message via nodemailer's MailComposer instead of SESv2's Content.Simple: an
// operational send can carry quote/invoice PDF attachments, which Content.Simple has no equivalent for.
// ---------------------------------------------------------------------------------------------------

export class OperationalSesEmailSubmissionError extends Error {
	constructor(
		message: string,
		public readonly outcome: 'retry' | 'cancelled' | 'submission_unknown',
		public readonly code: string
	) {
		super(message);
		this.name = 'OperationalSesEmailSubmissionError';
	}
}

export type OperationalSesEmail = {
	from: { email: string; name?: string };
	to: { email: string; name?: string } | { email: string; name?: string }[];
	replyTo?: { email: string; name?: string };
	subject: string;
	htmlContent: string;
	textContent: string;
	intentId: string;
	tenantName: string;
	configurationSetName: string;
	attachments?: { name: string; content: string }[];
};

function mailAddress(address: { email: string; name?: string }): {
	name?: string;
	address: string;
} {
	return { name: address.name, address: address.email };
}

async function buildRawOperationalMessage(message: OperationalSesEmail): Promise<Uint8Array> {
	const composer = new MailComposer({
		from: mailAddress(message.from),
		to: Array.isArray(message.to) ? message.to.map(mailAddress) : mailAddress(message.to),
		...(message.replyTo ? { replyTo: mailAddress(message.replyTo) } : {}),
		subject: message.subject,
		html: message.htmlContent,
		text: message.textContent,
		attachments: (message.attachments ?? []).map((attachment) => ({
			filename: attachment.name,
			content: attachment.content,
			encoding: 'base64' as const
		}))
	});
	return composer.compile().build();
}

export async function sendOperationalSesEmail(
	message: OperationalSesEmail
): Promise<{ messageId: string }> {
	const { client } = getSes();
	try {
		const raw = await buildRawOperationalMessage(message);
		const result = await client.send(
			new SendEmailCommand({
				Content: { Raw: { Data: raw } },
				ConfigurationSetName: message.configurationSetName,
				TenantName: message.tenantName,
				// SES echoes tags into mail.tags on the SNS delivery event, the SES-side equivalent of Brevo's
				// tags: ['ucrm:email:<id>'] -- this is what correlates a delivery event back to the intent.
				EmailTags: [{ Name: 'ucrm-intent', Value: message.intentId }]
			})
		);

		if (!result.MessageId)
			throw new OperationalSesEmailSubmissionError(
				'Amazon SES accepted the request without returning a message identifier.',
				'submission_unknown',
				'ses_missing_message_id'
			);
		return { messageId: result.MessageId };
	} catch (error) {
		if (error instanceof OperationalSesEmailSubmissionError) throw error;
		const status = sesStatus(error);
		const retryable = status === 429 || (status !== null && status >= 500);
		throw new OperationalSesEmailSubmissionError(
			`Amazon SES rejected the send${(error as AwsError)?.message ? `: ${(error as AwsError).message}` : '.'}`,
			status == null ? 'submission_unknown' : retryable ? 'retry' : 'cancelled',
			status == null ? 'ses_network_unknown' : `ses_${(error as AwsError)?.name ?? status}`
		);
	}
}

// ---------------------------------------------------------------------------------------------------
// Receipt rules (Operational email SES Part 4: customer replies). One rule per organization's reply subdomain,
// in the account's single active rule set (ucrm-ses-inbound-rules). Each rule's Recipients is that exact
// subdomain, so rules for different organizations never overlap and their order in the set never matters.
// ---------------------------------------------------------------------------------------------------

export type ReceiptRuleTarget = {
	bucketName: string;
	objectKeyPrefix: string;
	topicArn: string;
};

function isRuleNotFound(error: unknown): boolean {
	return (error as AwsError)?.name === 'RuleDoesNotExistException';
}

function desiredReceiptRule(
	ruleName: string,
	recipientDomain: string,
	target: ReceiptRuleTarget
): ReceiptRule {
	return {
		Name: ruleName,
		Enabled: true,
		ScanEnabled: true,
		Recipients: [recipientDomain],
		Actions: [
			{ S3Action: { BucketName: target.bucketName, ObjectKeyPrefix: target.objectKeyPrefix } },
			{ SNSAction: { TopicArn: target.topicArn, Encoding: 'UTF-8' } }
		]
	};
}

/**
 * Brings one organization's receipt rule to its desired state: created if missing, updated if its recipient or
 * actions have drifted. Never touches rule order -- Recipients is an exact subdomain, so this rule can never
 * shadow or be shadowed by another organization's.
 */
export async function reconcileSesReceiptRule(
	ruleSetName: string,
	ruleName: string,
	recipientDomain: string,
	target: ReceiptRuleTarget
): Promise<void> {
	const { client } = getSesV1();
	const desired = desiredReceiptRule(ruleName, recipientDomain, target);

	let existing: ReceiptRule | undefined;
	try {
		const described = await client.send(
			new DescribeReceiptRuleCommand({ RuleSetName: ruleSetName, RuleName: ruleName })
		);
		existing = described.Rule;
	} catch (error) {
		if (!isRuleNotFound(error)) throw toSesError('DescribeReceiptRule', error);
	}

	if (!existing) {
		try {
			await client.send(new CreateReceiptRuleCommand({ RuleSetName: ruleSetName, Rule: desired }));
		} catch (error) {
			if (!isAlreadyExists(error)) throw toSesError('CreateReceiptRule', error);
		}
		return;
	}

	const matches =
		existing.Recipients?.length === 1 &&
		existing.Recipients[0] === recipientDomain &&
		existing.Actions?.[0]?.S3Action?.BucketName === target.bucketName &&
		existing.Actions?.[0]?.S3Action?.ObjectKeyPrefix === target.objectKeyPrefix &&
		existing.Actions?.[1]?.SNSAction?.TopicArn === target.topicArn &&
		existing.Enabled === true;
	if (matches) return;

	await sesCall('UpdateReceiptRule', () =>
		client.send(new UpdateReceiptRuleCommand({ RuleSetName: ruleSetName, Rule: desired }))
	);
}

/** Deletes an organization's receipt rule. Already-gone is the desired state, so a retried removal is safe. */
export async function deleteSesReceiptRule(ruleSetName: string, ruleName: string): Promise<void> {
	const { client } = getSesV1();
	try {
		await client.send(
			new DeleteReceiptRuleCommand({ RuleSetName: ruleSetName, RuleName: ruleName })
		);
	} catch (error) {
		if (isRuleNotFound(error)) return;
		throw toSesError('DeleteReceiptRule', error);
	}
}
