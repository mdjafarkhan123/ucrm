// Dev helper: node scripts/cloudflare-add-cname.mjs <zoneName> <recordName> <cnameTarget> [--apply]
// Without --apply it only reads. With --apply it creates the CNAME (DNS only) if absent.
import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
	readFileSync('/home/jafar-khan/Documents/Projects/Ucrm/.env', 'utf8')
		.split('\n')
		.filter((l) => l.includes('=') && !l.trim().startsWith('#'))
		.map((l) => [
			l.slice(0, l.indexOf('=')).trim(),
			l
				.slice(l.indexOf('=') + 1)
				.trim()
				.replace(/^"|"$/g, '')
		])
);
const token = env.CLOUDFLARE_DNS_API_TOKEN;
const [zoneName, recordName, target] = process.argv.slice(2);
const apply = process.argv.includes('--apply');
const api = (path, init = {}) =>
	fetch(`https://api.cloudflare.com/client/v4${path}`, {
		...init,
		headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }
	}).then((r) => r.json());

const zones = await api(`/zones?name=${zoneName}`);
const zone = zones.result?.[0];
if (!zone) {
	console.log('zone not found', JSON.stringify(zones.errors));
	process.exit(1);
}
const existing = await api(`/zones/${zone.id}/dns_records?name=${recordName}`);
console.log(
	'zone',
	zone.name,
	'existing records at name:',
	JSON.stringify(
		existing.result?.map((r) => ({ type: r.type, content: r.content, proxied: r.proxied }))
	)
);
if (apply && existing.result?.length === 0) {
	const created = await api(`/zones/${zone.id}/dns_records`, {
		method: 'POST',
		body: JSON.stringify({
			type: 'CNAME',
			name: recordName,
			content: target,
			proxied: false,
			ttl: 300,
			comment: 'UCRM branded click tracking (CloudFront)'
		})
	});
	console.log('created', created.success, JSON.stringify(created.errors));
}
