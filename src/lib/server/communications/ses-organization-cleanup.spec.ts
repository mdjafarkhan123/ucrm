import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as ses from './ses';
import { teardownMarketingDomain } from './marketing-domain-activation';
import { teardownOperationalDomain } from './operational-domain-activation';
import { purgeOrganizationSesResources } from './ses-organization-cleanup';

vi.mock('./ses', () => ({
	deleteSesConfigurationSet: vi.fn(),
	deleteSesIdentity: vi.fn(),
	deleteSesTenant: vi.fn(),
	disassociateSesTenantResource: vi.fn(),
	listSesTenantResources: vi.fn(),
	sesConfigurationSetArn: vi.fn((name: string) => `arn:config-set/${name}`),
	sesIdentityArn: vi.fn((domain: string) => `arn:identity/${domain}`)
}));
vi.mock('./marketing-domain-activation', () => ({ teardownMarketingDomain: vi.fn() }));
vi.mock('./operational-domain-activation', () => ({ teardownOperationalDomain: vi.fn() }));

const ORG = '11111111-1111-1111-1111-111111111111';
const TENANT = `ucrm-org-${ORG}`;

beforeEach(() => {
	vi.clearAllMocks();
});

describe('purgeOrganizationSesResources', () => {
	it('unlinks every resource from the tenant before deleting it, then deletes the tenant', async () => {
		const order: string[] = [];
		vi.mocked(ses.listSesTenantResources).mockResolvedValue([
			{ type: 'EMAIL_IDENTITY', arn: 'arn:aws:ses:us-east-1:1:identity/mail.example.com' },
			{ type: 'EMAIL_IDENTITY', arn: 'arn:aws:ses:us-east-1:1:identity/news.example.com' },
			{ type: 'EMAIL_IDENTITY', arn: 'arn:aws:ses:us-east-1:1:identity/other.example.com' },
			{ type: 'CONFIGURATION_SET', arn: `arn:aws:ses:us-east-1:1:configuration-set/ucrm-${ORG}` }
		]);
		vi.mocked(ses.disassociateSesTenantResource).mockImplementation(async (_tenant, arn) => {
			order.push(`unlink:${arn}`);
		});
		vi.mocked(ses.deleteSesIdentity).mockImplementation(async (domain) => {
			order.push(`identity:${domain}`);
		});
		vi.mocked(ses.deleteSesConfigurationSet).mockImplementation(async (name) => {
			order.push(`config-set:${name}`);
		});
		vi.mocked(ses.deleteSesTenant).mockImplementation(async () => {
			order.push('tenant');
		});

		await purgeOrganizationSesResources(ORG);

		expect(teardownOperationalDomain).toHaveBeenCalledWith({
			organizationId: ORG,
			rootDomain: 'example.com'
		});
		expect(teardownMarketingDomain).toHaveBeenCalledWith({
			organizationId: ORG,
			rootDomain: 'example.com'
		});
		expect(ses.disassociateSesTenantResource).toHaveBeenCalledWith(
			TENANT,
			'arn:identity/other.example.com'
		);
		for (const name of [`ucrm-operational-${ORG}`, `ucrm-marketing-${ORG}`]) {
			expect(order.indexOf(`unlink:arn:config-set/${name}`)).toBe(
				order.indexOf(`config-set:${name}`) - 1
			);
		}
		expect(order.indexOf('unlink:arn:identity/other.example.com')).toBe(
			order.indexOf('identity:other.example.com') - 1
		);
		expect(order.at(-1)).toBe('tenant');
	});
});
