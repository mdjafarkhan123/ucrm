import { describe, expect, it } from 'vitest';
import { toCloudflareDnsRecord } from './cloudflare-dns';

describe('toCloudflareDnsRecord', () => {
	it('adds the sending subdomain to Brevo DKIM selector names', () => {
		expect(
			toCloudflareDnsRecord(
				{
					type: 'CNAME',
					host_name: 'brevo1._domainkey',
					value: 'b1.test-upliftcontractor-com.dkim.brevo.com',
					status: false
				},
				'test.upliftcontractor.com',
				'upliftcontractor.com'
			)
		).toMatchObject({
			cloudflare_name: 'brevo1._domainkey.test',
			content_label: 'Target',
			proxy_status: 'DNS only',
			ttl: 'Auto'
		});
	});

	it('leaves Brevo TXT names as zone-relative values', () => {
		expect(
			toCloudflareDnsRecord(
				{ type: 'TXT', host_name: '_dmarc.test', value: 'v=DMARC1; p=none', status: false },
				'test.upliftcontractor.com',
				'upliftcontractor.com'
			)
		).toMatchObject({
			cloudflare_name: '_dmarc.test',
			content_label: 'Content',
			proxy_status: null,
			ttl: 'Auto'
		});
	});
});
