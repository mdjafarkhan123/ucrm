import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { createBrevoDomain, getBrevoDomain } from '$lib/server/communications/brevo';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/brevo', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/brevo')>()),
	createBrevoDomain: vi.fn(),
	getBrevoDomain: vi.fn(),
	listBrevoDomains: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const currentDomainId = '123e4567-e89b-12d3-a456-426614174001';
const replacementDomainId = '123e4567-e89b-12d3-a456-426614174002';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174003';

function event(body: unknown) {
	const url = `http://localhost/api/jafar/organizations/${organizationId}/communications/domains/${currentDomainId}/replace`;
	return {
		params: { organizationId, domainId: currentDomainId },
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
	const updates: unknown[] = [];
	return {
		from: vi.fn(() => {
			const builder = query(results.shift() ?? { data: null, error: null });
			builder.insert = vi.fn((payload: unknown) => {
				inserts.push(payload);
				return builder;
			});
			builder.update = vi.fn((payload: unknown) => {
				updates.push(payload);
				return builder;
			});
			return builder;
		}),
		inserts,
		updates
	};
}

describe('owner sending-domain replacement boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
	});

	it('validates the command before database or provider access', async () => {
		const response = await POST(
			event({ domain_name: 'not a domain', idempotency_key: idempotencyKey })
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(getBrevoDomain).not.toHaveBeenCalled();
	});

	it('replays the immutable replacement receipt without provider I/O', async () => {
		const client = clientWithResults([
			{
				data: {
					target_id: replacementDomainId,
					after_state: {
						domain_name: 'mail-new.ridgeway.example',
						lifecycle_state: 'pending_dns'
					}
				},
				error: null
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				domain_name: 'mail-new.ridgeway.example',
				dns_zone: 'ridgeway.example',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			domain_id: replacementDomainId,
			replayed: true
		});
		expect(getBrevoDomain).not.toHaveBeenCalled();
	});

	it('persists the replacement claim before Brevo and leaves the current domain unchanged', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{
				data: {
					id: currentDomainId,
					domain_name: 'mail.ridgeway.example',
					purpose: 'sending',
					lifecycle_state: 'verified'
				},
				error: null
			},
			{ data: null, error: null },
			{
				data: {
					id: replacementDomainId,
					organization_id: organizationId,
					domain_name: 'mail-new.ridgeway.example',
					purpose: 'sending',
					provider_domain_id: null,
					lifecycle_state: 'pending_dns',
					replacement_of_domain_id: currentDomainId
				},
				error: null
			},
			{ data: null, error: null },
			{ data: null, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(getBrevoDomain)
			.mockImplementationOnce(async () => {
				expect(client.inserts).toContainEqual(
					expect.objectContaining({
						domain_name: 'mail-new.ridgeway.example',
						replacement_of_domain_id: currentDomainId
					})
				);
				const { BrevoManagementError } = await import('$lib/server/communications/brevo');
				throw new BrevoManagementError('Not found', 404, 'brevo_http_404');
			})
			.mockResolvedValueOnce({
				domain: 'mail-new.ridgeway.example',
				verified: false,
				authenticated: false,
				dns_records: []
			});
		vi.mocked(createBrevoDomain).mockResolvedValue({
			id: '6a8bb41bb9734c854105f2f5',
			domain_name: 'mail-new.ridgeway.example'
		});

		const response = await POST(
			event({
				domain_name: 'mail-new.ridgeway.example',
				dns_zone: 'ridgeway.example',
				idempotency_key: idempotencyKey
			})
		);
		const body = await response.json();

		expect(response.status).toBe(201);
		expect(body).toMatchObject({
			domain_id: replacementDomainId,
			current_domain_id: currentDomainId,
			current_domain_state: 'verified',
			lifecycle_state: 'pending_dns',
			queued_manual_email_policy: 'hold_for_review'
		});
		expect(client.updates).toHaveLength(1);
		expect(client.inserts).toContainEqual(
			expect.objectContaining({
				event_type: 'domain.replacement_provisioned',
				target_id: replacementDomainId,
				idempotency_key: idempotencyKey
			})
		);
	});

	it('does not replace a domain that is not currently verified', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{
				data: {
					id: currentDomainId,
					domain_name: 'mail.ridgeway.example',
					purpose: 'sending',
					lifecycle_state: 'unhealthy'
				},
				error: null
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				domain_name: 'mail-new.ridgeway.example',
				dns_zone: 'ridgeway.example',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(409);
		expect(getBrevoDomain).not.toHaveBeenCalled();
	});
});
