import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as activate } from './activate/+server';
import { POST as recheck } from './[domainId]/recheck/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	activateMarketingDomain,
	recheckMarketingDomain
} from '$lib/server/communications/marketing-domain-activation';
import { EmailDomainActivationError } from '$lib/server/communications/dns-reconcile';
import { CloudflareDnsError } from '$lib/server/communications/cloudflare-dns';
import { SesError } from '$lib/server/communications/ses-env';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/marketing-domain-activation', () => ({
	activateMarketingDomain: vi.fn(),
	recheckMarketingDomain: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174003';
const domainId = '123e4567-e89b-12d3-a456-426614174009';

const result = {
	root_domain: 'contractor.com',
	zone_id: 'zone-1',
	marketing: {
		domain_id: domainId,
		domain_name: 'news.contractor.com',
		mail_from_domain: 'bounce.news.contractor.com',
		lifecycle_state: 'verified',
		records_written: 5
	}
};

function query(outcome: { data: unknown; error: unknown }) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'neq']) builder[method] = vi.fn(() => builder);
	builder.maybeSingle = vi.fn(async () => outcome);
	builder.single = vi.fn(async () => outcome);
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(outcome).then(resolve);
	return builder;
}

function clientWithResults(results: Array<{ data: unknown; error: unknown }>) {
	const inserts: unknown[] = [];
	return {
		from: vi.fn(() => {
			const builder = query(results.shift() ?? { data: null, error: null });
			builder.insert = vi.fn((payload: unknown) => {
				inserts.push(payload);
				return builder;
			});
			builder.update = vi.fn(() => builder);
			return builder;
		}),
		inserts
	};
}

function activateEvent(body: unknown, params: Record<string, string> = { organizationId }) {
	const url = `http://localhost/api/jafar/organizations/${params.organizationId}/communications/marketing-domain/activate`;
	return {
		params,
		request: new Request(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof activate>[0];
}

function recheckEvent(
	body: unknown,
	params: Record<string, string> = { organizationId, domainId }
) {
	const url = `http://localhost/api/jafar/organizations/${params.organizationId}/communications/marketing-domain/${params.domainId}/recheck`;
	return {
		params,
		request: new Request(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof recheck>[0];
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	vi.mocked(getOwnerSession).mockResolvedValue({
		email: 'owner@example.com',
		sessionId: 'session-1',
		role: null,
		access: null,
		memberId: null,
		name: null
	});
	vi.mocked(activateMarketingDomain).mockResolvedValue(result as never);
	vi.mocked(recheckMarketingDomain).mockResolvedValue(result as never);
});

describe('owner Marketing sending-identity activation boundary', () => {
	const body = { root_domain: 'contractor.com', idempotency_key: idempotencyKey };

	it('refuses a request without an owner session before any database access', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(activateMarketingDomain).not.toHaveBeenCalled();
	});

	it('validates the root domain before database or provider access', async () => {
		const response = await activate(
			activateEvent({ root_domain: 'not a domain', idempotency_key: idempotencyKey })
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(activateMarketingDomain).not.toHaveBeenCalled();
	});

	it('stops a rate-limited owner without reconciling', async () => {
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: false, retryAfterSeconds: 42 });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(clientWithResults([]) as never);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(429);
		expect(activateMarketingDomain).not.toHaveBeenCalled();
	});

	it('replays the recorded receipt without provider I/O', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([
				{ data: { target_id: domainId, after_state: result }, error: null }
			]) as never
		);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ zone_id: 'zone-1', replayed: true });
		expect(activateMarketingDomain).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([
				{ data: null, error: null },
				{ data: null, error: null }
			]) as never
		);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(404);
		expect(activateMarketingDomain).not.toHaveBeenCalled();
	});

	it('reconciles for the organization in the route and records its own audit event type', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{ data: { id: organizationId }, error: null },
			{ data: null, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(201);
		expect(activateMarketingDomain).toHaveBeenCalledWith(
			expect.objectContaining({ organizationId, rootDomain: 'contractor.com' })
		);
		// A separate event type from 'domain.activated', so the operational history stays readable.
		expect(client.inserts).toContainEqual(
			expect.objectContaining({
				organization_id: organizationId,
				event_type: 'marketing_domain.activated',
				target_type: 'domain',
				target_id: domainId,
				idempotency_key: idempotencyKey
			})
		);
	});

	it('returns the recorded outcome when a concurrent activation already wrote the receipt', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([
				{ data: null, error: null },
				{ data: { id: organizationId }, error: null },
				{ data: null, error: { code: '23505' } },
				{ data: { after_state: result }, error: null }
			]) as never
		);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ replayed: true });
	});

	it('maps an occupied name to 409 with its code', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([
				{ data: null, error: null },
				{ data: { id: organizationId }, error: null }
			]) as never
		);
		vi.mocked(activateMarketingDomain).mockRejectedValue(
			new EmailDomainActivationError('That subdomain is in use.', 'subdomain_occupied', false)
		);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ code: 'subdomain_occupied' });
	});

	it('reports unconfigured SES as a service state rather than a retryable provider failure', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([
				{ data: null, error: null },
				{ data: { id: organizationId }, error: null }
			]) as never
		);
		vi.mocked(activateMarketingDomain).mockRejectedValue(
			new SesError('Amazon SES is not configured.', null, 'ses_not_configured')
		);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(503);
		expect(await response.json()).toMatchObject({ code: 'ses_not_configured' });
	});

	it('maps an ambiguous provider outcome to a retryable 503', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([
				{ data: null, error: null },
				{ data: { id: organizationId }, error: null }
			]) as never
		);
		vi.mocked(activateMarketingDomain).mockRejectedValue(
			new CloudflareDnsError('Cloudflare timed out', null, 'cloudflare_network_error')
		);

		const response = await activate(activateEvent(body));

		expect(response.status).toBe(503);
	});
});

describe('owner Marketing sending-identity recheck boundary', () => {
	const body = { idempotency_key: idempotencyKey };

	it('refuses a request without an owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await recheck(recheckEvent(body));

		expect(response.status).toBe(401);
		expect(recheckMarketingDomain).not.toHaveBeenCalled();
	});

	it('rejects an invalid domain identifier before touching providers', async () => {
		const response = await recheck(recheckEvent(body, { organizationId, domainId: 'not-a-uuid' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(recheckMarketingDomain).not.toHaveBeenCalled();
	});

	it('replays the recorded receipt without provider I/O', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([{ data: { after_state: result }, error: null }]) as never
		);

		const response = await recheck(recheckEvent(body));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ replayed: true });
		expect(recheckMarketingDomain).not.toHaveBeenCalled();
	});

	it('rechecks the domain in the route and records its audit event', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{ data: null, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await recheck(recheckEvent(body));

		expect(response.status).toBe(200);
		expect(recheckMarketingDomain).toHaveBeenCalledWith(
			expect.objectContaining({ organizationId, domainId })
		);
		expect(client.inserts).toContainEqual(
			expect.objectContaining({
				event_type: 'marketing_domain.rechecked',
				target_id: domainId,
				idempotency_key: idempotencyKey
			})
		);
	});

	it('maps a domain that is not a marketing identity to 409 with its code', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWithResults([{ data: null, error: null }]) as never
		);
		vi.mocked(recheckMarketingDomain).mockRejectedValue(
			new EmailDomainActivationError(
				'Marketing sending domain was not found.',
				'marketing_domain_not_found',
				false
			)
		);

		const response = await recheck(recheckEvent(body));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ code: 'marketing_domain_not_found' });
	});
});
