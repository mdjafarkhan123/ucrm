export type DnsRecord = {
	type: string;
	host_name: string;
	value: string;
	status: boolean;
};

export type CloudflareDnsRecord = DnsRecord & {
	cloudflare_name: string;
	content_label: 'Target' | 'Content';
	proxy_status: 'DNS only' | null;
	ttl: 'Auto';
};

function relativeSubdomain(domainName: string, dnsZone: string) {
	if (domainName === dnsZone) return '';
	const zoneSuffix = `.${dnsZone}`;
	return domainName.endsWith(zoneSuffix) ? domainName.slice(0, -zoneSuffix.length) : null;
}

export function toCloudflareDnsRecord(
	record: DnsRecord,
	domainName: string,
	dnsZone: string
): CloudflareDnsRecord {
	const subdomain = relativeSubdomain(domainName, dnsZone);
	const isDkimCname = record.type === 'CNAME' && record.host_name.endsWith('._domainkey');

	return {
		...record,
		cloudflare_name:
			isDkimCname && subdomain ? `${record.host_name}.${subdomain}` : record.host_name,
		content_label: record.type === 'CNAME' ? 'Target' : 'Content',
		proxy_status: record.type === 'CNAME' ? 'DNS only' : null,
		ttl: 'Auto'
	};
}
