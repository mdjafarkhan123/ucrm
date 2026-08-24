import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { getBrevoDomain } from '$lib/server/communications/brevo';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/brevo', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/brevo')>()),
	getBrevoDomain: vi.fn(),
	listBrevoDomains: vi.fn(),
	createBrevoDomain: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174001';

function event(body: unknown, id = organizationId) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/communications/domains`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		url: new URL(`http://localhost/api/jafar/organizations/${id}/communications/domains`),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('owner sending-domain provisioning boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('rejects a caller without the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await POST(
			event({
				domain_name: 'mail.ridgeway.example',
				dns_zone: 'ridgeway.example',
				purpose: 'sending',
				idempotency_key: idempotencyKey
			})
		);
		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('does not expose sending domains without the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await GET(event(null));
		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('validates the command before database or provider access', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		const response = await POST(
			event({
				domain_name: 'not a domain',
				dns_zone: 'ridgeway.example',
				purpose: 'sending',
				idempotency_key: idempotencyKey
			})
		);
		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(getBrevoDomain).not.toHaveBeenCalled();
	});

	it('replays the audited result without calling Brevo again', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		const receipt = {
			target_id: '123e4567-e89b-12d3-a456-426614174002',
			after_state: {
				domain_name: 'mail.ridgeway.example',
				purpose: 'sending',
				lifecycle_state: 'pending_dns'
			}
		};
		const maybeSingle = vi.fn().mockResolvedValue({ data: receipt, error: null });
		const builder: Record<string, ReturnType<typeof vi.fn>> = {};
		builder.select = vi.fn(() => builder);
		builder.eq = vi.fn(() => builder);
		builder.maybeSingle = maybeSingle;
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn(() => builder)
		} as never);

		const response = await POST(
			event({
				domain_name: 'mail.ridgeway.example',
				dns_zone: 'ridgeway.example',
				purpose: 'sending',
				idempotency_key: idempotencyKey
			})
		);
		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ domain_id: receipt.target_id, replayed: true });
		expect(getBrevoDomain).not.toHaveBeenCalled();
	});
});
