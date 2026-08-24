import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { BrevoManagementError, deleteBrevoDomain } from '$lib/server/communications/brevo';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/brevo', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/brevo')>()),
	deleteBrevoDomain: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const domainId = '123e4567-e89b-12d3-a456-426614174001';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174004';
const domain = {
	id: domainId,
	domain_name: 'mail.ridgeway.example',
	purpose: 'sending',
	lifecycle_state: 'verified',
	provider_domain_id: '6a8bb41bb9734c854105f2f5'
};

function event(method: 'GET' | 'POST', body?: unknown) {
	const url = `http://localhost/api/jafar/organizations/${organizationId}/communications/domains/${domainId}/remove`;
	return {
		params: { organizationId, domainId },
		request: new Request(url, {
			method,
			headers: body ? { 'content-type': 'application/json' } : undefined,
			body: body ? JSON.stringify(body) : undefined
		}),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function commandBody(impact = { live_sender_count: 0, live_replacement_count: 0 }) {
	return {
		confirm_domain_name: domain.domain_name,
		reason: 'Organization no longer uses this sending domain.',
		expected_impact: impact,
		idempotency_key: idempotencyKey
	};
}

type Result = { data?: unknown; error?: unknown; count?: number | null };

function clientWithResults(
	results: Result[],
	rpcResults: Result[] = [
		{
			data: {
				status: 'started',
				live_sender_count: 0,
				live_replacement_count: 0,
				previous_lifecycle_state: 'verified'
			}
		},
		{
			data: {
				status: 'completed',
				domain_name: domain.domain_name,
				purpose: 'sending',
				lifecycle_state: 'removed',
				provider_cleanup_confirmed: true,
				removed_at: '2026-08-24T01:00:00.000Z'
			}
		}
	]
) {
	const updates: unknown[] = [];
	const inserts: unknown[] = [];
	return {
		from: vi.fn(() => {
			const result = results.shift() ?? { data: null, error: null };
			const builder: Record<string, unknown> = {};
			for (const method of ['select', 'eq', 'neq']) builder[method] = vi.fn(() => builder);
			builder.update = vi.fn((payload: unknown) => {
				updates.push(payload);
				return builder;
			});
			builder.insert = vi.fn((payload: unknown) => {
				inserts.push(payload);
				return builder;
			});
			builder.maybeSingle = vi.fn(async () => ({
				data: result.data ?? null,
				error: result.error ?? null
			}));
			builder.single = vi.fn(async () => ({
				data: result.data ?? null,
				error: result.error ?? null
			}));
			builder.then = (resolve: (value: unknown) => unknown) =>
				Promise.resolve({
					data: result.data ?? null,
					error: result.error ?? null,
					count: result.count ?? null
				}).then(resolve);
			return builder;
		}),
		rpc: vi.fn(async () => {
			const result = rpcResults.shift() ?? { data: null, error: null };
			return { data: result.data ?? null, error: result.error ?? null };
		}),
		updates,
		inserts
	};
}

describe('owner sending-domain removal boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
	});

	it('returns a bounded current impact preview', async () => {
		const client = clientWithResults([{ data: domain }, { count: 2 }, { count: 1 }]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await GET(event('GET'));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			domain_name: domain.domain_name,
			impact: { live_sender_count: 2, live_replacement_count: 1 },
			can_remove: false
		});
	});

	it('rejects a stale impact confirmation before provider cleanup', async () => {
		const client = clientWithResults(
			[{ data: null }, { data: domain }],
			[
				{
					data: {
						status: 'impact_changed',
						live_sender_count: 1,
						live_replacement_count: 0
					}
				}
			]
		);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event('POST', commandBody()));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({
			impact: { live_sender_count: 1, live_replacement_count: 0 }
		});
		expect(deleteBrevoDomain).not.toHaveBeenCalled();
	});

	it('replays a confirmed removal without calling Brevo', async () => {
		const client = clientWithResults([
			{
				data: {
					target_id: domainId,
					after_state: { domain_name: domain.domain_name, lifecycle_state: 'removed' }
				}
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event('POST', commandBody()));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ lifecycle_state: 'removed', replayed: true });
		expect(deleteBrevoDomain).not.toHaveBeenCalled();
	});

	it('keeps an ambiguous Brevo deletion visible and retryable', async () => {
		const client = clientWithResults([{ data: null }, { data: domain }, {}]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(deleteBrevoDomain).mockRejectedValue(
			new BrevoManagementError('No response', null, 'brevo_network_unknown')
		);

		const response = await POST(event('POST', commandBody()));

		expect(response.status).toBe(502);
		expect(await response.json()).toMatchObject({
			lifecycle_state: 'removal_pending',
			retryable: true
		});
		expect(client.updates).toEqual([
			expect.objectContaining({ provider_cleanup_error: 'brevo_network_unknown' })
		]);
	});

	it('treats Brevo not-found as confirmed cleanup and records the receipt', async () => {
		const client = clientWithResults([{ data: null }, { data: domain }, {}]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(deleteBrevoDomain).mockRejectedValue(
			new BrevoManagementError('Not found', 404, 'brevo_http_404')
		);

		const response = await POST(event('POST', commandBody()));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			domain_id: domainId,
			lifecycle_state: 'removed',
			provider_cleanup_confirmed: true
		});
		expect(client.rpc).toHaveBeenNthCalledWith(
			2,
			'finalize_communication_email_domain_removal',
			expect.objectContaining({
				actor_owner_email: 'owner@example.com',
				removal_reason: 'Organization no longer uses this sending domain.',
				command_idempotency_key: idempotencyKey
			})
		);
	});
});
