import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	activateEmailDomain,
	EmailDomainActivationError
} from '$lib/server/communications/email-domain-activation';
import { CloudflareDnsError } from '$lib/server/communications/cloudflare-dns';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/email-domain-activation', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/email-domain-activation')>()),
	activateEmailDomain: vi.fn()
}));
vi.mock('$lib/server/email/env', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/email/env')>()),
	getBrevoInboundWebhookUrl: vi.fn(() => 'https://app.example.com/api/webhooks/brevo/inbound')
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174003';
const sendingDomainId = '123e4567-e89b-12d3-a456-426614174009';

const activationResult = {
	zone_id: 'zone-1',
	sending: { domain_id: sendingDomainId, domain_name: 'mail.contractor.com', records_written: 3 },
	receiving: { domain_name: 'reply.contractor.com', provider_inbound_webhook_id: '4242' }
};

function event(body: unknown, params: Record<string, string> = { organizationId }) {
	const url = `http://localhost/api/jafar/organizations/${params.organizationId}/communications/domains/activate`;
	return {
		params,
		request: new Request(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function query(result: { data: unknown; error: unknown }) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'neq']) builder[method] = vi.fn(() => builder);
	builder.maybeSingle = vi.fn(async () => result);
	builder.single = vi.fn(async () => result);
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
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

function validBody() {
	return { root_domain: 'contractor.com', idempotency_key: idempotencyKey };
}

describe('owner managed email-domain activation boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		vi.mocked(activateEmailDomain).mockResolvedValue(activationResult as never);
	});

	it('refuses a request without an owner session before any database access', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(activateEmailDomain).not.toHaveBeenCalled();
	});

	it('rejects an invalid organization identifier before touching providers', async () => {
		const response = await POST(event(validBody(), { organizationId: 'not-a-uuid' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(activateEmailDomain).not.toHaveBeenCalled();
	});

	it('validates the root domain before database or provider access', async () => {
		const response = await POST(
			event({ root_domain: 'not a domain', idempotency_key: idempotencyKey })
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(activateEmailDomain).not.toHaveBeenCalled();
	});

	it('stops a rate-limited owner without reconciling', async () => {
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: false, retryAfterSeconds: 42 });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(clientWithResults([]) as never);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(429);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(activateEmailDomain).not.toHaveBeenCalled();
	});

	it('replays the recorded activation receipt without provider I/O', async () => {
		const client = clientWithResults([
			{
				data: {
					target_id: sendingDomainId,
					after_state: activationResult
				},
				error: null
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ zone_id: 'zone-1', replayed: true });
		expect(activateEmailDomain).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		const client = clientWithResults([
			{ data: null, error: null }, // no receipt
			{ data: null, error: null } // organization not found
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(404);
		expect(activateEmailDomain).not.toHaveBeenCalled();
	});

	it('reconciles for the organization in the route and records the audit event', async () => {
		const client = clientWithResults([
			{ data: null, error: null }, // no receipt
			{ data: { id: organizationId }, error: null }, // organization exists
			{ data: null, error: null } // audit insert succeeds
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(201);
		expect(await response.json()).toMatchObject({ zone_id: 'zone-1' });
		expect(activateEmailDomain).toHaveBeenCalledWith(
			expect.objectContaining({ organizationId, rootDomain: 'contractor.com' })
		);
		expect(client.inserts).toContainEqual(
			expect.objectContaining({
				organization_id: organizationId,
				event_type: 'domain.activated',
				target_id: sendingDomainId,
				idempotency_key: idempotencyKey
			})
		);
	});

	it('returns the recorded outcome when a concurrent activation already wrote the receipt', async () => {
		const client = clientWithResults([
			{ data: null, error: null }, // no receipt on first read
			{ data: { id: organizationId }, error: null }, // organization exists
			{ data: null, error: { code: '23505' } }, // audit insert loses the race
			{ data: { after_state: activationResult }, error: null } // replay read of the winner
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ zone_id: 'zone-1', replayed: true });
	});

	it('maps a non-retryable activation conflict to 409 with its code', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{ data: { id: organizationId }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(activateEmailDomain).mockRejectedValue(
			new EmailDomainActivationError('That subdomain is in use.', 'subdomain_occupied', false)
		);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ code: 'subdomain_occupied' });
	});

	it('maps an ambiguous provider outcome to a retryable 502', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{ data: { id: organizationId }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(activateEmailDomain).mockRejectedValue(
			new CloudflareDnsError('Cloudflare timed out', null, 'cloudflare_network_error')
		);

		const response = await POST(event(validBody()));

		expect(response.status).toBe(502);
	});
});
