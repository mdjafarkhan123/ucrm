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
	PutEmailIdentityMailFromAttributesCommand,
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

// The seven event types the provisioned SNS -> SQS pipeline was proven against. Engagement events (open,
// click, subscription) are deliberately absent: Marketing does not render tracking pixels or rewrite links
// in this release, so subscribing to them would only add noise.
const MARKETING_EVENT_TYPES: EventType[] = [
	'SEND',
	'DELIVERY',
	'BOUNCE',
	'COMPLAINT',
	'REJECT',
	'DELIVERY_DELAY',
	'RENDERING_FAILURE'
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
	const alreadyAttached = (existing.EventDestinations ?? []).some(
		(destination) => destination.SnsDestination?.TopicArn === env.AWS_SES_EVENT_SNS_TOPIC_ARN
	);
	if (alreadyAttached) return true;

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
