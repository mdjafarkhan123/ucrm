import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { SesError } from './ses-env';

vi.mock('./cloudfront', () => ({
	getClickDomainEnv: vi.fn(),
	getClickTenant: vi.fn(),
	createClickTenant: vi.fn(),
	getClickTenantCertificate: vi.fn(),
	updateClickTenant: vi.fn(),
	deleteClickTenant: vi.fn()
}));

vi.mock('./ses', () => ({
	getSesClickTrackingDomain: vi.fn(),
	putSesClickTrackingDomain: vi.fn()
}));

vi.mock('./cloudflare-dns', async () => {
	const actual = await vi.importActual<typeof import('./cloudflare-dns')>('./cloudflare-dns');
	return {
		...actual,
		resolveCloudflareZone: vi.fn(),
		listCloudflareDnsRecords: vi.fn(),
		createCloudflareDnsRecord: vi.fn(),
		updateCloudflareDnsRecord: vi.fn(),
		deleteCloudflareDnsRecord: vi.fn()
	};
});

const resolveCname = vi.fn();
vi.mock('node:dns/promises', () => ({
	Resolver: class {
		setServers() {}
		resolveCname = resolveCname;
	}
}));

import * as cloudfront from './cloudfront';
import * as ses from './ses';
import * as cloudflare from './cloudflare-dns';
import { changeClickDomain, reconcileClickDomain } from './branded-click-domain';

const ORG = '11111111-1111-1111-1111-111111111111';
const DOMAIN_ID = '22222222-2222-2222-2222-222222222222';
const MARKETING = 'news.contractor.com';
const CLICK = 'click.news.contractor.com';
const CONFIG_SET = `ucrm-marketing-${ORG}`;
const ENV = {
	AWS_CLICK_DISTRIBUTION_ID: 'E3BC29BRFLB91P',
	AWS_CLICK_CONNECTION_GROUP_ID: 'cg_abc',
	AWS_CLICK_ROUTING_ENDPOINT: 'd30azkeso6lzew.cloudfront.net'
};

type Row = Record<string, unknown>;

function baseRow(overrides: Row = {}): Row {
	return {
		id: DOMAIN_ID,
		organization_id: ORG,
		domain_name: MARKETING,
		dns_zone: 'contractor.com',
		purpose: 'marketing_sending',
		lifecycle_state: 'verified',
		click_domain_status: 'not_set_up',
		click_domain_name: null,
		click_distribution_tenant_id: null,
		click_domain_error: null,
		click_domain_checked_at: null,
		...overrides
	};
}

/** Answers the one row lookup and records every update. */
function fakeClient(row: Row) {
	const updates: Row[] = [];
	const client = {
		from: () => {
			const chain = {
				select: () => chain,
				eq: () => chain,
				neq: () => chain,
				maybeSingle: async () => ({ data: row, error: null }),
				update: (values: Row) => {
					updates.push(values);
					return { eq: async () => ({ error: null }) };
				}
			};
			return chain;
		}
	} as unknown as SupabaseClient<Database>;
	return { client, updates };
}

function tenant(overrides: Partial<cloudfront.ClickTenant> = {}): cloudfront.ClickTenant {
	return {
		id: 'dt_1',
		etag: 'E1',
		name: `ucrm-org-${ORG}`,
		distributionId: ENV.AWS_CLICK_DISTRIBUTION_ID,
		connectionGroupId: ENV.AWS_CLICK_CONNECTION_GROUP_ID,
		domains: [{ domain: CLICK, active: true }],
		certificateArn: 'arn:aws:acm:us-east-1:1:certificate/c',
		enabled: true,
		deployed: true,
		...overrides
	};
}

function answersHealthCheck(ok: boolean) {
	vi.stubGlobal(
		'fetch',
		vi.fn(
			async () =>
				new Response(null, { headers: ok ? { 'x-amz-ses-request-protocol': 'https' } : {} })
		)
	);
}

beforeEach(() => {
	vi.resetAllMocks();
	vi.unstubAllGlobals();
	vi.mocked(cloudfront.getClickDomainEnv).mockReturnValue(ENV);
	vi.mocked(cloudflare.listCloudflareDnsRecords).mockResolvedValue([]);
	vi.mocked(cloudflare.resolveCloudflareZone).mockResolvedValue({
		id: 'zone-1',
		name: 'contractor.com'
	});
	vi.mocked(ses.getSesClickTrackingDomain).mockResolvedValue(null);
	resolveCname.mockResolvedValue([ENV.AWS_CLICK_ROUTING_ENDPOINT]);
});

describe('reconcileClickDomain', () => {
	it('brands links only after the click domain answers over HTTPS', async () => {
		const { client, updates } = fakeClient(baseRow());
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(tenant());
		answersHealthCheck(true);

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(cloudflare.createCloudflareDnsRecord).toHaveBeenCalledWith('zone-1', {
			type: 'CNAME',
			name: CLICK,
			content: ENV.AWS_CLICK_ROUTING_ENDPOINT,
			proxied: false
		});
		expect(ses.putSesClickTrackingDomain).toHaveBeenCalledWith(CONFIG_SET, CLICK);
		expect(summary.status).toBe('working');
		expect(updates.at(-1)).toMatchObject({
			click_domain_status: 'working',
			click_domain_name: CLICK,
			click_distribution_tenant_id: 'dt_1'
		});
	});

	it('creates the tenant and waits while the certificate is pending, keeping Amazon links', async () => {
		const { client } = fakeClient(baseRow());
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(null);
		vi.mocked(cloudfront.createClickTenant).mockResolvedValue(tenant({ certificateArn: null }));
		vi.mocked(cloudfront.getClickTenantCertificate).mockResolvedValue({
			arn: 'arn:c',
			status: 'pending-validation'
		});
		vi.mocked(ses.getSesClickTrackingDomain).mockResolvedValue(CLICK);

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(cloudfront.createClickTenant).toHaveBeenCalledWith({
			env: ENV,
			name: `ucrm-org-${ORG}`,
			domain: CLICK
		});
		expect(summary.status).toBe('waiting_certificate');
		expect(ses.putSesClickTrackingDomain).toHaveBeenCalledWith(CONFIG_SET, null);
	});

	it('waits without creating the tenant until public DNS shows the new CNAME', async () => {
		const { client } = fakeClient(baseRow());
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(null);
		resolveCname.mockRejectedValue(Object.assign(new Error('ENOTFOUND'), { code: 'ENOTFOUND' }));

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(cloudfront.createClickTenant).not.toHaveBeenCalled();
		expect(summary.status).toBe('waiting_certificate');
		expect(summary.error).toContain('Press Check again');
	});

	it('waits when CloudFront cannot see the CNAME yet, instead of reporting a problem', async () => {
		const { client } = fakeClient(baseRow());
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(null);
		vi.mocked(cloudfront.createClickTenant).mockResolvedValue('dns_not_ready');

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(summary.status).toBe('waiting_certificate');
		expect(ses.putSesClickTrackingDomain).not.toHaveBeenCalled();
	});

	it('attaches an issued certificate, then waits while the tenant redeploys', async () => {
		const { client } = fakeClient(baseRow());
		const bare = tenant({ certificateArn: null });
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(bare);
		vi.mocked(cloudfront.getClickTenantCertificate).mockResolvedValue({
			arn: 'arn:issued',
			status: 'issued'
		});
		vi.mocked(cloudfront.updateClickTenant).mockResolvedValue(
			tenant({ certificateArn: 'arn:issued', deployed: false })
		);
		answersHealthCheck(false);

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(cloudfront.updateClickTenant).toHaveBeenCalledWith(bare, {
			certificateArn: 'arn:issued'
		});
		expect(summary.status).toBe('waiting_certificate');
		expect(ses.putSesClickTrackingDomain).not.toHaveBeenCalled();
	});

	it('records a problem and returns links to Amazon when a deployed domain does not answer', async () => {
		const { client } = fakeClient(
			baseRow({
				click_domain_status: 'working',
				click_domain_name: CLICK,
				click_distribution_tenant_id: 'dt_1'
			})
		);
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(tenant());
		vi.mocked(ses.getSesClickTrackingDomain).mockResolvedValue(CLICK);
		answersHealthCheck(false);

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(summary.status).toBe('problem');
		expect(summary.error).toContain('not answering');
		expect(ses.putSesClickTrackingDomain).toHaveBeenCalledWith(CONFIG_SET, null);
	});

	it('keeps a working domain working when a provider does not answer', async () => {
		const { client } = fakeClient(
			baseRow({
				click_domain_status: 'working',
				click_domain_name: CLICK,
				click_distribution_tenant_id: 'dt_1'
			})
		);
		vi.mocked(cloudfront.getClickTenant).mockRejectedValue(
			new SesError('timeout', null, 'cloudfront_network_unknown')
		);

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(summary.status).toBe('working');
		expect(summary.error).toContain('Press Check again');
		expect(ses.putSesClickTrackingDomain).not.toHaveBeenCalled();
	});

	it('does nothing when the owner turned branded links off', async () => {
		const { client, updates } = fakeClient(baseRow({ click_domain_status: 'turned_off' }));

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(summary.status).toBe('turned_off');
		expect(updates).toHaveLength(0);
		expect(cloudfront.getClickTenant).not.toHaveBeenCalled();
	});

	it('does nothing on a server without the shared distribution', async () => {
		vi.mocked(cloudfront.getClickDomainEnv).mockReturnValue(null);
		const { client, updates } = fakeClient(baseRow());

		const summary = await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(summary).toMatchObject({ status: 'not_set_up', configured: false });
		expect(updates).toHaveLength(0);
	});

	it('waits for the sending identity to be verified', async () => {
		const { client, updates } = fakeClient(baseRow({ lifecycle_state: 'pending_dns' }));

		await reconcileClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			zoneId: 'zone-1'
		});

		expect(updates).toHaveLength(0);
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});
});

describe('changeClickDomain', () => {
	const workingRow = () =>
		baseRow({
			click_domain_status: 'working',
			click_domain_name: CLICK,
			click_distribution_tenant_id: 'dt_1'
		});

	it('turning off returns links to Amazon and keeps the tenant', async () => {
		const { client, updates } = fakeClient(workingRow());
		vi.mocked(ses.getSesClickTrackingDomain).mockResolvedValue(CLICK);

		const summary = await changeClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			action: 'turn_off'
		});

		expect(ses.putSesClickTrackingDomain).toHaveBeenCalledWith(CONFIG_SET, null);
		expect(summary.status).toBe('turned_off');
		expect(updates.at(-1)).toMatchObject({ click_distribution_tenant_id: 'dt_1' });
		expect(cloudfront.deleteClickTenant).not.toHaveBeenCalled();
	});

	it('removing disables and deletes the tenant, then its CNAME', async () => {
		const { client, updates } = fakeClient(workingRow());
		const disabled = tenant({ enabled: false });
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(tenant());
		vi.mocked(cloudfront.updateClickTenant).mockResolvedValue(disabled);
		vi.mocked(cloudfront.deleteClickTenant).mockResolvedValue('deleted');
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockResolvedValue([
			{
				id: 'rec-1',
				type: 'CNAME',
				name: CLICK,
				content: ENV.AWS_CLICK_ROUTING_ENDPOINT,
				ttl: 1,
				priority: null,
				proxied: false
			}
		]);

		const summary = await changeClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			action: 'remove'
		});

		expect(cloudfront.updateClickTenant).toHaveBeenCalledWith(expect.anything(), {
			enabled: false
		});
		expect(cloudfront.deleteClickTenant).toHaveBeenCalledWith(disabled);
		expect(cloudflare.deleteCloudflareDnsRecord).toHaveBeenCalledWith('zone-1', 'rec-1');
		expect(summary).toMatchObject({ status: 'turned_off', domain_name: null });
		expect(updates.at(-1)).toMatchObject({ click_distribution_tenant_id: null });
	});

	it('removing reports that it is finishing while Amazon still deploys the disable', async () => {
		const { client } = fakeClient(workingRow());
		vi.mocked(cloudfront.getClickTenant).mockResolvedValue(tenant());
		vi.mocked(cloudfront.updateClickTenant).mockResolvedValue(tenant({ enabled: false }));
		vi.mocked(cloudfront.deleteClickTenant).mockResolvedValue('not_ready');

		const summary = await changeClickDomain({
			client,
			organizationId: ORG,
			domainId: DOMAIN_ID,
			action: 'remove'
		});

		expect(summary.error).toContain('Press Remove again');
		expect(cloudflare.deleteCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('refuses to turn on before the Marketing domain is verified', async () => {
		const { client } = fakeClient(
			baseRow({ lifecycle_state: 'pending_dns', click_domain_status: 'turned_off' })
		);

		await expect(
			changeClickDomain({ client, organizationId: ORG, domainId: DOMAIN_ID, action: 'turn_on' })
		).rejects.toMatchObject({ code: 'marketing_domain_not_verified' });
	});
});
