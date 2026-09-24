import {
	CloudFrontClient,
	CreateDistributionTenantCommand,
	DeleteDistributionTenantCommand,
	GetDistributionTenantCommand,
	GetManagedCertificateDetailsCommand,
	UpdateDistributionTenantCommand,
	type DistributionTenant
} from '@aws-sdk/client-cloudfront';
import { env } from '$env/dynamic/private';
import { z } from 'zod';
import { getSesEnv, SesError } from './ses-env';

// Server-only CloudFront adapter for Marketing branded click domains (M6d). Like ses.ts it exposes thin,
// idempotent primitives and nothing about which domain an organization should have; the branded click domain
// reconciler owns that policy.
//
// One multi-tenant distribution (origin: SES's regional tracking endpoint) and its connection group are set up
// once per AWS account, by hand (docs/research/ses-branded-click-tracking-domain-2026-09-24.md). Each
// organization is a distribution tenant on it. The app uses the same IAM user as SES, whose policy
// (scripts/aws/ucrm-branded-click-domain-policy.json) allows tenant actions only, never distribution changes.

const CLOUDFRONT_REQUEST_TIMEOUT_MS = 10_000;

const clickEnvSchema = z.object({
	AWS_CLICK_DISTRIBUTION_ID: z
		.string()
		.trim()
		.regex(/^[A-Z0-9]{8,20}$/),
	AWS_CLICK_CONNECTION_GROUP_ID: z
		.string()
		.trim()
		.regex(/^cg_[A-Za-z0-9]+$/),
	AWS_CLICK_ROUTING_ENDPOINT: z
		.string()
		.trim()
		.toLowerCase()
		.regex(/^[a-z0-9]+\.cloudfront\.net$/)
});

export type ClickDomainEnv = z.infer<typeof clickEnvSchema>;

/**
 * The shared distribution settings, or null when this server has none. Branded links are optional: a server
 * without them keeps Amazon's default tracking links and every other Marketing step still works.
 */
export function getClickDomainEnv(): ClickDomainEnv | null {
	const result = clickEnvSchema.safeParse({
		AWS_CLICK_DISTRIBUTION_ID: env.AWS_CLICK_DISTRIBUTION_ID,
		AWS_CLICK_CONNECTION_GROUP_ID: env.AWS_CLICK_CONNECTION_GROUP_ID,
		AWS_CLICK_ROUTING_ENDPOINT: env.AWS_CLICK_ROUTING_ENDPOINT
	});
	return result.success ? result.data : null;
}

let cached: CloudFrontClient | null = null;

function getCloudFront(): CloudFrontClient {
	if (cached) return cached;
	const sesEnv = getSesEnv();
	// CloudFront is a global service whose control plane lives in us-east-1.
	cached = new CloudFrontClient({
		region: 'us-east-1',
		credentials: {
			accessKeyId: sesEnv.AWS_SES_ACCESS_KEY_ID,
			secretAccessKey: sesEnv.AWS_SES_SECRET_ACCESS_KEY
		},
		requestHandler: { requestTimeout: CLOUDFRONT_REQUEST_TIMEOUT_MS, connectionTimeout: 5_000 }
	});
	return cached;
}

type AwsError = { name?: string; message?: string; $metadata?: { httpStatusCode?: number } };

function awsStatus(error: unknown): number | null {
	return (error as AwsError)?.$metadata?.httpStatusCode ?? null;
}

function isNotFound(error: unknown): boolean {
	return (error as AwsError)?.name === 'EntityNotFound' || awsStatus(error) === 404;
}

/**
 * Same error contract as ses.ts: a SesError with the HTTP status, where a missing status means the outcome is
 * unknown and the reconciler re-derives it from provider state on the next pass.
 */
function toCloudFrontError(operation: string, error: unknown): SesError {
	const status = awsStatus(error);
	const detail = (error as AwsError)?.message;
	return new SesError(
		`Amazon CloudFront rejected ${operation}${detail ? `: ${detail}` : '.'}`,
		status,
		status == null
			? 'cloudfront_network_unknown'
			: `cloudfront_${(error as AwsError)?.name ?? status}`
	);
}

export type ClickTenant = {
	id: string;
	etag: string;
	name: string;
	distributionId: string;
	connectionGroupId: string | null;
	domains: { domain: string; active: boolean }[];
	certificateArn: string | null;
	enabled: boolean;
	deployed: boolean;
};

function toClickTenant(
	tenant: DistributionTenant | undefined,
	etag: string | undefined
): ClickTenant {
	if (!tenant?.Id || !etag) {
		throw new SesError(
			'Amazon CloudFront returned a tenant without an id or version.',
			null,
			'cloudfront_tenant_unreadable'
		);
	}
	return {
		id: tenant.Id,
		etag,
		name: tenant.Name ?? '',
		distributionId: tenant.DistributionId ?? '',
		connectionGroupId: tenant.ConnectionGroupId ?? null,
		domains: (tenant.Domains ?? []).map((domain) => ({
			domain: (domain.Domain ?? '').toLowerCase(),
			active: domain.Status === 'active'
		})),
		certificateArn: tenant.Customizations?.Certificate?.Arn ?? null,
		enabled: tenant.Enabled ?? false,
		deployed: tenant.Status === 'Deployed'
	};
}

/** Reads a tenant by id, ARN, or name. Returns null when it does not exist. */
export async function getClickTenant(identifier: string): Promise<ClickTenant | null> {
	try {
		const result = await getCloudFront().send(
			new GetDistributionTenantCommand({ Identifier: identifier })
		);
		return toClickTenant(result.DistributionTenant, result.ETag);
	} catch (error) {
		if (isNotFound(error)) return null;
		throw toCloudFrontError('GetDistributionTenant', error);
	}
}

/**
 * Creates the organization's tenant with a CloudFront-managed certificate. With ValidationTokenHost
 * 'cloudfront', CloudFront proves domain control through the CNAME that already points at the routing
 * endpoint, so no separate validation record is written.
 */
export async function createClickTenant(input: {
	env: ClickDomainEnv;
	name: string;
	domain: string;
}): Promise<ClickTenant | 'dns_not_ready'> {
	try {
		const result = await getCloudFront().send(
			new CreateDistributionTenantCommand({
				DistributionId: input.env.AWS_CLICK_DISTRIBUTION_ID,
				ConnectionGroupId: input.env.AWS_CLICK_CONNECTION_GROUP_ID,
				Name: input.name,
				Domains: [{ Domain: input.domain }],
				Enabled: true,
				ManagedCertificateRequest: {
					ValidationTokenHost: 'cloudfront',
					PrimaryDomainName: input.domain,
					CertificateTransparencyLoggingPreference: 'enabled'
				}
			})
		);
		return toClickTenant(result.DistributionTenant, result.ETag);
	} catch (error) {
		// CloudFront refuses a domain whose DNS it cannot yet see pointing at it. A freshly written CNAME takes
		// minutes to reach CloudFront's resolvers (found in the live remove-and-turn-on test), so this is a
		// "try again shortly", not a failure.
		if (
			(error as AwsError)?.name === 'InvalidArgument' &&
			/verify domain name ownership|not be pointing/i.test((error as AwsError)?.message ?? '')
		) {
			return 'dns_not_ready';
		}
		// A create that raced another pass: the tenant exists, so read it back.
		if ((error as AwsError)?.name === 'EntityAlreadyExists') {
			const existing = await getClickTenant(input.name);
			if (existing) return existing;
		}
		throw toCloudFrontError('CreateDistributionTenant', error);
	}
}

export type ManagedCertificateStatus =
	| 'pending-validation'
	| 'issued'
	| 'inactive'
	| 'expired'
	| 'validation-timed-out'
	| 'revoked'
	| 'failed';

export async function getClickTenantCertificate(
	tenantId: string
): Promise<{ arn: string | null; status: ManagedCertificateStatus | null } | null> {
	try {
		const result = await getCloudFront().send(
			new GetManagedCertificateDetailsCommand({ Identifier: tenantId })
		);
		const details = result.ManagedCertificateDetails;
		return {
			arn: details?.CertificateArn ?? null,
			status: (details?.CertificateStatus as ManagedCertificateStatus | undefined) ?? null
		};
	} catch (error) {
		if (isNotFound(error)) return null;
		throw toCloudFrontError('GetManagedCertificateDetails', error);
	}
}

/**
 * Updates a tenant, re-sending everything it already has so nothing is dropped: an update replaces the
 * tenant's domains and customizations rather than merging them. The ETag guards against a concurrent change.
 */
export async function updateClickTenant(
	tenant: ClickTenant,
	change: { certificateArn?: string; enabled?: boolean }
): Promise<ClickTenant> {
	const certificateArn = change.certificateArn ?? tenant.certificateArn;
	try {
		const result = await getCloudFront().send(
			new UpdateDistributionTenantCommand({
				Id: tenant.id,
				IfMatch: tenant.etag,
				DistributionId: tenant.distributionId,
				ConnectionGroupId: tenant.connectionGroupId ?? undefined,
				Domains: tenant.domains.map((domain) => ({ Domain: domain.domain })),
				Customizations: certificateArn ? { Certificate: { Arn: certificateArn } } : undefined,
				Enabled: change.enabled ?? tenant.enabled
			})
		);
		return toClickTenant(result.DistributionTenant, result.ETag);
	} catch (error) {
		throw toCloudFrontError('UpdateDistributionTenant', error);
	}
}

/**
 * Deletes a disabled tenant. Returns 'not_ready' when CloudFront still considers it enabled or in flight, so
 * the caller can report that removal is finishing rather than treating it as a failure.
 */
export async function deleteClickTenant(tenant: ClickTenant): Promise<'deleted' | 'not_ready'> {
	try {
		await getCloudFront().send(
			new DeleteDistributionTenantCommand({ Id: tenant.id, IfMatch: tenant.etag })
		);
		return 'deleted';
	} catch (error) {
		if (isNotFound(error)) return 'deleted';
		const name = (error as AwsError)?.name;
		if (name === 'ResourceNotDisabled' || name === 'PreconditionFailed') return 'not_ready';
		throw toCloudFrontError('DeleteDistributionTenant', error);
	}
}
