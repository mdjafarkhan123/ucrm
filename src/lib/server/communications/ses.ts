import {
	SESv2Client,
	CreateConfigurationSetCommand,
	CreateConfigurationSetEventDestinationCommand,
	CreateEmailIdentityCommand,
	CreateTenantCommand,
	CreateTenantResourceAssociationCommand,
	GetConfigurationSetCommand,
	GetConfigurationSetEventDestinationsCommand,
	GetEmailIdentityCommand,
	GetTenantCommand,
	PutConfigurationSetTrackingOptionsCommand,
	PutEmailIdentityMailFromAttributesCommand,
	SendEmailCommand,
	UpdateConfigurationSetEventDestinationCommand,
	type EventType
} from '@aws-sdk/client-sesv2';
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
// unsubscribe is UCRM-owned.
const MARKETING_EVENT_TYPES: EventType[] = [
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
				DkimSigningAttributes: { DomainSigningAttributesOrigin: 'AWS_SES' }
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
		if (MARKETING_EVENT_TYPES.every((type) => current.has(type)) && attached.Enabled) return true;
		await sesCall('UpdateConfigurationSetEventDestination', () =>
			client.send(
				new UpdateConfigurationSetEventDestinationCommand({
					ConfigurationSetName: configurationSetName,
					EventDestinationName: attached.Name,
					EventDestination: {
						Enabled: true,
						MatchingEventTypes: MARKETING_EVENT_TYPES,
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
					MatchingEventTypes: MARKETING_EVENT_TYPES,
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
