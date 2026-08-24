import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	authenticateBrevoDomain,
	BrevoManagementError,
	getBrevoDomain
} from '$lib/server/communications/brevo';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/brevo', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/brevo')>()),
	authenticateBrevoDomain: vi.fn(),
	getBrevoDomain: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const domainId = '123e4567-e89b-12d3-a456-426614174001';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174002';

function event(body: unknown) {
	const url = `http://localhost/api/jafar/organizations/${organizationId}/communications/domains/${domainId}/recheck`;
	return {
		params: { organizationId, domainId },
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
	for (const method of ['select', 'eq', 'neq', 'update']) {
		builder[method] = vi.fn(() => builder);
	}
	builder.maybeSingle = vi.fn(async () => result);
	builder.single = vi.fn(async () => result);
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return builder;
}

function clientWithResults(results: Array<{ data: unknown; error: unknown }>) {
	const updates: unknown[] = [];
	const inserts: unknown[] = [];
	return {
		from: vi.fn(() => {
			const builder = query(results.shift() ?? { data: null, error: null });
			builder.update = vi.fn((payload: unknown) => {
				updates.push(payload);
				return builder;
			});
			builder.insert = vi.fn((payload: unknown) => {
				inserts.push(payload);
				return builder;
			});
			return builder;
		}),
		updates,
		inserts
	};
}

describe('owner sending-domain recheck boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
	});

	it('rejects an invalid command before database or provider access', async () => {
		const response = await POST(event({ idempotency_key: 'reuse-this' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(authenticateBrevoDomain).not.toHaveBeenCalled();
	});

	it('replays the immutable receipt without calling Brevo again', async () => {
		const client = clientWithResults([
			{
				data: {
					target_id: domainId,
					after_state: { lifecycle_state: 'verified', provider_authenticated: true }
				},
				error: null
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			domain_id: domainId,
			lifecycle_state: 'verified',
			replayed: true
		});
		expect(authenticateBrevoDomain).not.toHaveBeenCalled();
	});

	it('persists verified authority and an immutable receipt after a passing recheck', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{
				data: {
					id: domainId,
					domain_name: 'mail.ridgeway.example',
					purpose: 'sending',
					lifecycle_state: 'pending_dns',
					spf_status: 'unchecked',
					verified_at: null,
					provider_domain_id: '6a8bb41bb9734c854105f2f5'
				},
				error: null
			},
			{ data: null, error: null },
			{ data: null, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(authenticateBrevoDomain).mockResolvedValue(null);
		vi.mocked(getBrevoDomain).mockResolvedValue({
			domain: 'mail.ridgeway.example',
			verified: true,
			authenticated: true,
			dns_records: [
				{ type: 'TXT', host_name: '@', value: 'brevo-code:abc', status: true },
				{ type: 'TXT', host_name: 'sib1._domainkey', value: 'dkim', status: true },
				{ type: 'TXT', host_name: '_dmarc', value: 'v=DMARC1; p=none', status: true }
			]
		});

		const response = await POST(event({ idempotency_key: idempotencyKey }));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(authenticateBrevoDomain).toHaveBeenCalledWith('mail.ridgeway.example');
		expect(getBrevoDomain).toHaveBeenCalledWith('mail.ridgeway.example');
		expect(body).toMatchObject({
			domain_id: domainId,
			lifecycle_state: 'verified',
			ownership_status: 'passing',
			dkim_status: 'passing',
			spf_status: 'unchecked'
		});
		expect(client.updates).toContainEqual(
			expect.objectContaining({ lifecycle_state: 'verified', provider_authenticated: true })
		);
		expect(client.inserts).toContainEqual(
			expect.objectContaining({ event_type: 'domain.rechecked', idempotency_key: idempotencyKey })
		);
	});

	it('records a DNS failure as unhealthy after a domain had been verified', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{
				data: {
					id: domainId,
					domain_name: 'mail.ridgeway.example',
					purpose: 'sending',
					lifecycle_state: 'verified',
					spf_status: 'unchecked',
					verified_at: '2026-08-24T00:00:00.000Z',
					provider_domain_id: '6a8bb41bb9734c854105f2f5'
				},
				error: null
			},
			{ data: null, error: null },
			{ data: null, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(authenticateBrevoDomain).mockRejectedValue(
			new BrevoManagementError('DNS mismatch', 400, 'brevo_http_400')
		);
		vi.mocked(getBrevoDomain).mockResolvedValue({
			domain: 'mail.ridgeway.example',
			verified: true,
			authenticated: false,
			dns_records: [
				{ type: 'TXT', host_name: '@', value: 'brevo-code:abc', status: true },
				{ type: 'TXT', host_name: 'sib1._domainkey', value: 'dkim', status: false }
			]
		});

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			lifecycle_state: 'unhealthy',
			provider_authenticated: false,
			dkim_status: 'failing'
		});
	});
});
