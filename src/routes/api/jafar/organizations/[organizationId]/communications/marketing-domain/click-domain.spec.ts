import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './[domainId]/click-domain/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { changeClickDomain } from '$lib/server/communications/branded-click-domain';
import { EmailDomainActivationError } from '$lib/server/communications/dns-reconcile';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/branded-click-domain', () => ({
	changeClickDomain: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const domainId = '123e4567-e89b-12d3-a456-426614174009';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174003';

const click = {
	status: 'turned_off',
	domain_name: 'click.news.contractor.com',
	error: null,
	checked_at: '2026-09-24T00:00:00.000Z',
	configured: true
};

function clientWith(receipt: unknown) {
	const inserts: unknown[] = [];
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'neq']) builder[method] = vi.fn(() => builder);
	builder.maybeSingle = vi.fn(async () => ({ data: receipt, error: null }));
	builder.insert = vi.fn(async (payload: unknown) => {
		inserts.push(payload);
		return { error: null };
	});
	return { client: { from: vi.fn(() => builder) }, inserts };
}

function event(body: unknown) {
	const url = `http://localhost/api/jafar/organizations/${organizationId}/communications/marketing-domain/${domainId}/click-domain`;
	return {
		params: { organizationId, domainId },
		request: new Request(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		url: new URL(url),
		cookies: {}
	} as unknown as Parameters<typeof POST>[0];
}

describe('owner branded click-link controls', () => {
	beforeEach(() => {
		vi.resetAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		} as Awaited<ReturnType<typeof getOwnerSession>>);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('rejects a non-owner', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await POST(event({ action: 'turn_off', idempotency_key: idempotencyKey }));
		expect(response.status).toBe(401);
		expect(changeClickDomain).not.toHaveBeenCalled();
	});

	it('rejects an unknown action before touching anything', async () => {
		const { client } = clientWith(null);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const response = await POST(event({ action: 'delete_all', idempotency_key: idempotencyKey }));
		expect(response.status).toBe(422);
		expect(changeClickDomain).not.toHaveBeenCalled();
	});

	it('runs the change and records an audit receipt', async () => {
		const { client, inserts } = clientWith(null);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(changeClickDomain).mockResolvedValue(click as never);

		const response = await POST(event({ action: 'turn_off', idempotency_key: idempotencyKey }));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ click });
		expect(changeClickDomain).toHaveBeenCalledWith({
			client,
			organizationId,
			domainId,
			action: 'turn_off'
		});
		expect(inserts[0]).toMatchObject({
			event_type: 'marketing_domain.click_domain.turn_off',
			target_id: domainId,
			idempotency_key: idempotencyKey
		});
	});

	it('replays a repeated request instead of changing twice', async () => {
		const { client } = clientWith({ after_state: { click } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ action: 'turn_off', idempotency_key: idempotencyKey }));

		expect(await response.json()).toEqual({ click, replayed: true });
		expect(changeClickDomain).not.toHaveBeenCalled();
	});

	it('returns a conflict for a decision the owner must make', async () => {
		const { client } = clientWith(null);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(changeClickDomain).mockRejectedValue(
			new EmailDomainActivationError(
				'The Marketing domain must be verified before branded links can be turned on.',
				'marketing_domain_not_verified',
				false
			)
		);

		const response = await POST(event({ action: 'turn_on', idempotency_key: idempotencyKey }));

		expect(response.status).toBe(409);
	});
});
