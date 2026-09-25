import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { recheckOperationalDomain } from '$lib/server/communications/operational-domain-activation';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/operational-domain-activation', () => ({
	recheckOperationalDomain: vi.fn()
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
		expect(recheckOperationalDomain).not.toHaveBeenCalled();
	});

	it('replays the immutable receipt without calling the providers again', async () => {
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
		expect(recheckOperationalDomain).not.toHaveBeenCalled();
	});

	it('refuses a domain that is not on Amazon SES', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{ data: { id: domainId, purpose: 'sending', provider: 'brevo' }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(404);
		expect(recheckOperationalDomain).not.toHaveBeenCalled();
	});

	it('re-runs the Amazon SES activation for a domain on SES and records the receipt', async () => {
		const client = clientWithResults([
			{ data: null, error: null },
			{
				data: { id: domainId, purpose: 'sending', provider: 'ses' },
				error: null
			},
			{ data: null, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(recheckOperationalDomain).mockResolvedValue({
			sending: {
				domain_id: domainId,
				domain_name: 'mail.ridgeway.example',
				lifecycle_state: 'verified'
			},
			receiving: { domain_name: 'reply.ridgeway.example', lifecycle_state: 'pending_dns' }
		} as never);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(200);
		expect(recheckOperationalDomain).toHaveBeenCalledWith(
			expect.objectContaining({ organizationId, domainId })
		);
		expect(await response.json()).toMatchObject({
			domain_id: domainId,
			lifecycle_state: 'verified',
			receiving: { domain_name: 'reply.ridgeway.example', lifecycle_state: 'pending_dns' }
		});
		expect(client.inserts).toContainEqual(
			expect.objectContaining({ event_type: 'domain.rechecked', idempotency_key: idempotencyKey })
		);
	});
});
