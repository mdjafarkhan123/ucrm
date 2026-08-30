import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { env } from '$env/dynamic/private';
import {
	CloudflareDnsError,
	createCloudflareDnsRecord,
	deleteCloudflareDnsRecord,
	listCloudflareDnsRecords,
	resolveCloudflareZoneId
} from './cloudflare-dns';

vi.mock('$env/dynamic/private', () => ({ env: {} as Record<string, string | undefined> }));

const mutableEnv = env as Record<string, string | undefined>;

function envelope(result: unknown, extra: Record<string, unknown> = {}) {
	return new Response(JSON.stringify({ success: true, errors: [], result, ...extra }), {
		status: 200
	});
}

describe('Cloudflare DNS adapter', () => {
	beforeEach(() => {
		vi.stubGlobal('fetch', vi.fn());
		mutableEnv.CLOUDFLARE_DNS_API_TOKEN = 'server-only-dns-token';
	});

	afterEach(() => {
		vi.unstubAllGlobals();
		delete mutableEnv.CLOUDFLARE_DNS_API_TOKEN;
	});

	it('refuses to act when the token is not configured', async () => {
		delete mutableEnv.CLOUDFLARE_DNS_API_TOKEN;

		await expect(resolveCloudflareZoneId('upliftcontractor.com')).rejects.toMatchObject({
			code: 'cloudflare_not_configured'
		});
		expect(fetch).not.toHaveBeenCalled();
	});

	it('sends the bearer token and resolves an apex zone on the first, exact match', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			envelope([{ id: 'zone-123', name: 'upliftcontractor.com' }])
		);

		await expect(resolveCloudflareZoneId('upliftcontractor.com')).resolves.toBe('zone-123');

		// An apex that is itself a zone resolves in exactly one call -- no parent walk.
		expect(fetch).toHaveBeenCalledTimes(1);
		const [url, init] = vi.mocked(fetch).mock.calls[0];
		expect(url).toBe(
			'https://api.cloudflare.com/client/v4/zones?name=upliftcontractor.com&status=active'
		);
		expect(init!.headers).toMatchObject({ authorization: 'Bearer server-only-dns-token' });
	});

	it('walks up to the parent zone and takes the longest (most specific) match', async () => {
		// The token cannot see a zone for the subdomain itself, only for the registrable apex above it.
		vi.mocked(fetch)
			.mockResolvedValueOnce(envelope([])) // reply.test.upliftcontractor.com -> not a zone
			.mockResolvedValueOnce(envelope([])) // test.upliftcontractor.com -> not a zone
			.mockResolvedValueOnce(envelope([{ id: 'zone-uplift', name: 'upliftcontractor.com' }]));

		await expect(resolveCloudflareZoneId('reply.test.upliftcontractor.com')).resolves.toBe(
			'zone-uplift'
		);

		// It queried most-specific first and stopped at the first confirmed zone.
		const queried = vi
			.mocked(fetch)
			.mock.calls.map(([url]) => new URL(String(url)).searchParams.get('name'));
		expect(queried).toEqual([
			'reply.test.upliftcontractor.com',
			'test.upliftcontractor.com',
			'upliftcontractor.com'
		]);
	});

	it('refuses when no managed zone contains the domain, never querying a bare TLD', async () => {
		vi.mocked(fetch)
			.mockResolvedValueOnce(envelope([])) // mail.notours.com
			.mockResolvedValueOnce(envelope([])); // notours.com

		await expect(resolveCloudflareZoneId('mail.notours.com')).rejects.toMatchObject({
			code: 'cloudflare_zone_unresolved'
		});

		// Two candidates only: the domain and its registrable apex -- 'com' alone is never asked for.
		const queried = vi
			.mocked(fetch)
			.mock.calls.map(([url]) => new URL(String(url)).searchParams.get('name'));
		expect(queried).toEqual(['mail.notours.com', 'notours.com']);
	});

	it('ignores a zone whose name is not the exact candidate (boundary validation)', async () => {
		// Cloudflare's name filter is exact, but guard anyway: a superstring match is not our zone, so the
		// apex candidate finds nothing usable and the resolver refuses rather than adopting a foreign zone.
		vi.mocked(fetch).mockResolvedValueOnce(
			envelope([{ id: 'zone-evil', name: 'evil-upliftcontractor.com' }])
		);

		await expect(resolveCloudflareZoneId('upliftcontractor.com')).rejects.toMatchObject({
			code: 'cloudflare_zone_unresolved'
		});
		expect(fetch).toHaveBeenCalledTimes(1);
	});

	it('refuses to guess when one apex resolves to two active zones', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			envelope([
				{ id: 'zone-a', name: 'upliftcontractor.com' },
				{ id: 'zone-b', name: 'upliftcontractor.com' }
			])
		);
		await expect(resolveCloudflareZoneId('upliftcontractor.com')).rejects.toMatchObject({
			code: 'cloudflare_zone_unresolved'
		});
	});

	it('normalizes records at a name, defaulting a missing priority and proxied flag', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			envelope([
				{
					id: 'rec-1',
					type: 'MX',
					name: 'reply.test.upliftcontractor.com',
					content: 'inbound1.sendinblue.com',
					ttl: 3600,
					priority: 10
				},
				{
					id: 'rec-2',
					type: 'TXT',
					name: 'reply.test.upliftcontractor.com',
					content: 'brevo-code:xyz',
					ttl: 1
				}
			])
		);

		await expect(
			listCloudflareDnsRecords('zone-123', 'reply.test.upliftcontractor.com')
		).resolves.toEqual([
			{
				id: 'rec-1',
				type: 'MX',
				name: 'reply.test.upliftcontractor.com',
				content: 'inbound1.sendinblue.com',
				ttl: 3600,
				priority: 10,
				proxied: false
			},
			{
				id: 'rec-2',
				type: 'TXT',
				name: 'reply.test.upliftcontractor.com',
				content: 'brevo-code:xyz',
				ttl: 1,
				priority: null,
				proxied: false
			}
		]);
	});

	it('creates a record exactly as asked, keeping mail records DNS-only', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			envelope({
				id: 'rec-new',
				type: 'MX',
				name: 'reply.test.upliftcontractor.com',
				content: 'inbound1.sendinblue.com',
				ttl: 3600,
				priority: 10,
				proxied: false
			})
		);

		await createCloudflareDnsRecord('zone-123', {
			type: 'MX',
			name: 'reply.test.upliftcontractor.com',
			content: 'inbound1.sendinblue.com',
			priority: 10,
			proxied: false
		});

		const [url, init] = vi.mocked(fetch).mock.calls[0];
		expect(url).toBe('https://api.cloudflare.com/client/v4/zones/zone-123/dns_records');
		expect(init!.method).toBe('POST');
		expect(JSON.parse(init!.body as string)).toEqual({
			type: 'MX',
			name: 'reply.test.upliftcontractor.com',
			content: 'inbound1.sendinblue.com',
			priority: 10,
			proxied: false
		});
	});

	it('treats a network failure or abort as retryable-unknown, never a proven write', async () => {
		vi.mocked(fetch).mockRejectedValueOnce(new DOMException('aborted', 'AbortError'));

		await expect(
			createCloudflareDnsRecord('zone-123', {
				type: 'TXT',
				name: 'mail.upliftcontractor.com',
				content: 'brevo-code:xyz',
				proxied: false
			})
		).rejects.toMatchObject({ code: 'cloudflare_network_unknown', status: null });
	});

	it('never reports a Cloudflare application error as success', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({
					success: false,
					errors: [{ code: 81044, message: 'Record already exists.' }]
				}),
				{ status: 200 }
			)
		);

		await expect(
			createCloudflareDnsRecord('zone-123', {
				type: 'TXT',
				name: 'mail.upliftcontractor.com',
				content: 'brevo-code:xyz',
				proxied: false
			})
		).rejects.toBeInstanceOf(CloudflareDnsError);
	});

	it('treats a missing record as already deleted so cleanup is retryable', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ success: false, errors: [{ code: 81044 }] }), { status: 404 })
		);

		await expect(deleteCloudflareDnsRecord('zone-123', 'rec-gone')).resolves.toBeUndefined();
		expect(fetch).toHaveBeenCalledWith(
			'https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/rec-gone',
			expect.objectContaining({ method: 'DELETE' })
		);
	});
});
