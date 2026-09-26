import { teardownOperationalDomain } from './operational-domain-activation';
import {
	deleteSesConfigurationSet,
	deleteSesIdentity,
	deleteSesTenant,
	listSesTenantResources
} from './ses';
import {
	marketingConfigurationSetName,
	operationalConfigurationSetName,
	sesTenantName
} from './ses-domain-identity';

const IDENTITY_ARN_MARKER = ':identity/';

/**
 * Removes every Amazon SES resource a purged organization owned, found from its organization id alone: the
 * tenant lists the identities and configuration sets associated with it, so no domain name ever has to be
 * stored on the deletion receipt. An everyday sending identity (mail.<root>) gets the same full teardown as
 * Remove -- replies, reply identity, and the DNS records UCRM wrote. Every step treats "already gone" as
 * done, so the closure sweep can safely retry after a partial failure.
 */
export async function purgeOrganizationSesResources(organizationId: string): Promise<void> {
	const tenantName = sesTenantName(organizationId);
	const identities = (await listSesTenantResources(tenantName))
		.filter((resource) => resource.type === 'EMAIL_IDENTITY')
		.map((resource) =>
			resource.arn.slice(resource.arn.indexOf(IDENTITY_ARN_MARKER) + IDENTITY_ARN_MARKER.length)
		);

	for (const domain of identities) {
		if (domain.startsWith('mail.')) {
			await teardownOperationalDomain({ organizationId, rootDomain: domain.slice('mail.'.length) });
		} else {
			await deleteSesIdentity(domain);
		}
	}

	await deleteSesConfigurationSet(operationalConfigurationSetName(organizationId));
	await deleteSesConfigurationSet(marketingConfigurationSetName(organizationId));
	await deleteSesTenant(tenantName);
}
