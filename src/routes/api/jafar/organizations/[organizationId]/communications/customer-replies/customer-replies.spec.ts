import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	activateReplyIngestion,
	ReplyIngestionNotReadyError
} from '$lib/server/communications/operational-reply-ingestion';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/communications/operational-reply-ingestion', async (importOriginal) => ({
	...(await importOriginal<
		typeof import('$lib/server/communications/operational-reply-ingestion')
	>()),
	activateReplyIngestion: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174003';

const activationResult = {
	domain_id: '123e4567-e89b-12d3-a456-426614174009',
	domain_name: 'reply.contractor.com',
	lifecycle_state: 'pending_dns',
	inbound_mx_status: 'pending',
	records_written: 2
};

function event(body: unknown, params: Record<string, string> = { organizationId }) {
	const url = `http://localhost/api/jafar/organizations/${params.organizationId}/communications/customer-replies`;
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
	for (const method of ['select', 'eq', 'neq', 'order', 'limit'])
		builder[method] = vi.fn(() => builder);
	builder.maybeSingle = vi.fn(async () => result);
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return builder;
}

// Results are handed out in call order: receipt lookup, sending-domain lookup, then the audit insert.
function clientWithResults(results: Array<{ data: unknown; error: unknown }>) {
	const inserts: unknown[] = [];
	return {
		from: vi.fn(() => {
			const builder = query(results.shift() ?? { data: null, error: null });
			builder.insert = vi.fn((payload: unknown) => {
				inserts.push(payload);
				return builder;
			});
			return builder;
		}),
		inserts
	};
}

const noReceipt = { data: null, error: null };
const verifiedSending = { data: { dns_zone: 'contractor.com' }, error: null };

describe('owner customer-replies activation boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		vi.mocked(activateReplyIngestion).mockResolvedValue(activationResult as never);
	});

	it('refuses a request without an owner session before any database access', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		expect(activateReplyIngestion).not.toHaveBeenCalled();
	});

	it('validates the body before database or provider access', async () => {
		const response = await POST(event({ idempotency_key: 'nope' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('ignores any domain in the request and uses the verified sending domain zone', async () => {
		const client = clientWithResults([noReceipt, verifiedSending, noReceipt]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({ idempotency_key: idempotencyKey, root_domain: 'someone-else.com' })
		);

		expect(response.status).toBe(200);
		expect(activateReplyIngestion).toHaveBeenCalledWith(
			expect.objectContaining({ organizationId, rootDomain: 'contractor.com' })
		);
		expect(client.inserts[0]).toMatchObject({
			event_type: 'reply_ingestion.activated',
			actor_owner_email: 'owner@example.com',
			target_id: activationResult.domain_id
		});
	});

	it('refuses when everyday email is not ready, without touching providers', async () => {
		const client = clientWithResults([noReceipt, { data: null, error: null }]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(409);
		expect(activateReplyIngestion).not.toHaveBeenCalled();
	});

	it('replays a recorded receipt without provider I/O', async () => {
		const client = clientWithResults([{ data: { after_state: activationResult }, error: null }]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ replayed: true });
		expect(activateReplyIngestion).not.toHaveBeenCalled();
	});

	it('explains a reply subdomain SES has not verified yet as a 409, not a provider failure', async () => {
		const client = clientWithResults([noReceipt, verifiedSending]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		vi.mocked(activateReplyIngestion).mockRejectedValue(
			new ReplyIngestionNotReadyError(
				'reply.contractor.com is not a verified Amazon SES identity yet.'
			)
		);

		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('not a verified Amazon SES identity');
	});
});
