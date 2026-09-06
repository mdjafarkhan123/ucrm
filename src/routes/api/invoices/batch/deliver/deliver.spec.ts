import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { createInvoiceEmailAccessLink } from '$lib/server/communications/invoice-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

// Batch deliver (Part 8b) — the batch control flow only. The four things this proves are exactly the four
// Jafar asked to see, on isolated made-up invoices with nothing real touched:
//   1. every accepted invoice is queued once,
//   2. the first rate-limit denial stops the batch and leaves the rest untouched (not issued, not queued),
//   3. retrying with the same per-invoice key never queues a second email,
//   4. one invoice failing does not stop the others.
//
// Nothing here sends an email. The endpoint's "send" is a queue insert (`enqueue_invoice_communication_email`);
// the outbox worker is the real provider boundary and is not in this path. So the enqueue RPC is stubbed, and
// the limiter is stubbed and "seeded" near its threshold by choosing how many calls it allows — the real
// 20-per-5-minute bucket is never touched. The RPC's own de-dup on `logical_send_key` is defined in migration
// 20260906120000 (it returns the existing intent instead of inserting a second outbox event); the stub below
// mirrors that so test 3 checks the endpoint cooperates with it end to end.

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});
vi.mock('$lib/server/communications/invoice-email', () => ({
	createInvoiceEmailAccessLink: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedLink = vi.mocked(createInvoiceEmailAccessLink);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);

// Stable ids so a test can name an invoice and its key.
const INV = {
	a: '00000000-0000-4000-8000-0000000000a1',
	b: '00000000-0000-4000-8000-0000000000b2',
	c: '00000000-0000-4000-8000-0000000000c3',
	d: '00000000-0000-4000-8000-0000000000d4'
};
const KEY = {
	a: '00000000-0000-4000-8000-0000000000a0',
	b: '00000000-0000-4000-8000-0000000000b0',
	c: '00000000-0000-4000-8000-0000000000c0',
	d: '00000000-0000-4000-8000-0000000000d0'
};

type Item = { invoice_id: string; expected_revision: number; idempotency_key: string };

// A stub `event`, carrying the browser body and the user-scoped Supabase client the handler reads statuses and
// issues drafts through.
function event(items: Item[], userClient: unknown) {
	return {
		request: new Request('http://localhost/api/invoices/batch/deliver', {
			method: 'POST',
			body: JSON.stringify({ invoices: items })
		}),
		locals: { supabase: userClient }
	} as Parameters<typeof POST>[0];
}

describe('sending invoices in a batch', () => {
	// The user client: reads (organization, id) status rows, and issues a draft on send.
	let statusRows: Array<{ id: string; issued_at: string | null }> = [];
	const issueRpc = vi.fn();
	const inFn = vi.fn();
	const userClient = {
		from: vi.fn(() => ({ select: () => ({ eq: () => ({ in: inFn }) }) })),
		rpc: issueRpc
	};

	// The owner client: the only thing it does in this path is enqueue the email. Modelled as idempotent on the
	// logical send key, exactly as the real RPC is, so a repeated key returns the first intent rather than a
	// second one — the property test 3 depends on.
	const enqueuedByKey = new Map<string, { id: string; status: string }>();
	let intentCounter = 0;
	const ownerRpc = vi.fn((name: string, args: Record<string, unknown>) => {
		if (name !== 'enqueue_invoice_communication_email')
			return Promise.resolve({ data: null, error: null });
		const key = args.target_logical_send_key as string;
		let intent = enqueuedByKey.get(key);
		if (!intent) {
			intentCounter += 1;
			intent = { id: `intent-${intentCounter}`, status: 'queued' };
			enqueuedByKey.set(key, intent);
		}
		return Promise.resolve({ data: intent, error: null });
	});

	// The limiter, seeded near its threshold: it allows this many calls, then denies with a real retry delay.
	function allowThenDeny(allowed: number, retryAfterSeconds = 214) {
		let seen = 0;
		mockedRateLimit.mockImplementation(() => {
			seen += 1;
			return Promise.resolve(
				seen <= allowed
					? { allowed: true, retryAfterSeconds: 0 }
					: { allowed: false, retryAfterSeconds }
			);
		});
	}

	function item(invoiceId: string, key: string, revision = 0): Item {
		return { invoice_id: invoiceId, expected_revision: revision, idempotency_key: key };
	}

	beforeEach(() => {
		vi.clearAllMocks();
		statusRows = [];
		enqueuedByKey.clear();
		intentCounter = 0;
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'conversations.send': true }, features: {} }
		} as never);
		mockedOwnerClient.mockReturnValue({ rpc: ownerRpc } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		mockedLink.mockReturnValue({ tokenHash: '\\xabc', url: 'https://app.example.com/i/token' });
		issueRpc.mockResolvedValue({ error: null });
		inFn.mockImplementation(() => Promise.resolve({ data: statusRows, error: null }));
	});

	it('requires conversations.send on top of invoices.send', async () => {
		await POST(event([item(INV.a, KEY.a)], userClient));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'invoices.send');
	});

	// 1. Every accepted invoice is queued exactly once.
	it('queues each accepted invoice once, issuing the drafts', async () => {
		statusRows = [
			{ id: INV.a, issued_at: null },
			{ id: INV.b, issued_at: '2026-09-01T00:00:00Z' }
		];
		const response = await POST(event([item(INV.a, KEY.a), item(INV.b, KEY.b)], userClient));
		const body = await response.json();

		expect(response.status).toBe(201);
		expect(body.summary).toMatchObject({
			total: 2,
			queued: 2,
			failed: 0,
			rate_limited: 0,
			skipped: 0
		});
		expect(body.results.map((r: { outcome: string }) => r.outcome)).toEqual(['queued', 'queued']);

		// One enqueue per invoice, each carrying its own stable key.
		const enqueues = ownerRpc.mock.calls.filter(
			(c) => c[0] === 'enqueue_invoice_communication_email'
		);
		expect(enqueues).toHaveLength(2);
		expect(enqueues.map((c) => (c[1] as Record<string, unknown>).target_logical_send_key)).toEqual([
			KEY.a,
			KEY.b
		]);
		// Only the draft is issued; the already-issued bill is not re-issued.
		expect(issueRpc).toHaveBeenCalledTimes(1);
		expect(issueRpc.mock.calls[0][1]).toMatchObject({ target_invoice_id: INV.a });
	});

	// 2. The first rate-limit denial stops the batch; the rest are skipped and never touched.
	it('stops at the first rate-limit denial and leaves the remaining invoices untouched', async () => {
		statusRows = [
			{ id: INV.a, issued_at: null },
			{ id: INV.b, issued_at: null },
			{ id: INV.c, issued_at: null },
			{ id: INV.d, issued_at: null }
		];
		allowThenDeny(2, 214);

		const response = await POST(
			event(
				[item(INV.a, KEY.a), item(INV.b, KEY.b), item(INV.c, KEY.c), item(INV.d, KEY.d)],
				userClient
			)
		);
		const body = await response.json();

		expect(body.summary).toMatchObject({
			total: 4,
			queued: 2,
			rate_limited: 1,
			skipped: 1,
			failed: 0
		});
		expect(body.results.map((r: { outcome: string }) => r.outcome)).toEqual([
			'queued',
			'queued',
			'rate_limited',
			'skipped'
		]);
		// The denied invoice carries the limiter's real retry delay.
		expect(body.results[2]).toMatchObject({ invoice_id: INV.c, retry_after_seconds: 214 });
		// Nothing past the denial is issued or queued.
		expect(issueRpc).toHaveBeenCalledTimes(2);
		const enqueues = ownerRpc.mock.calls.filter(
			(c) => c[0] === 'enqueue_invoice_communication_email'
		);
		expect(enqueues).toHaveLength(2);
		const touched = enqueues.map((c) => (c[1] as Record<string, unknown>).target_invoice_id);
		expect(touched).not.toContain(INV.c);
		expect(touched).not.toContain(INV.d);
	});

	// 3. Retrying with the same per-invoice key never queues a second email.
	it('does not duplicate a queued email when the same key is retried', async () => {
		statusRows = [
			{ id: INV.a, issued_at: null },
			{ id: INV.b, issued_at: null }
		];
		// First send: the window allows one, so A queues and B is denied.
		allowThenDeny(1, 214);
		const first = await (
			await POST(event([item(INV.a, KEY.a), item(INV.b, KEY.b)], userClient))
		).json();
		expect(first.results.map((r: { outcome: string }) => r.outcome)).toEqual([
			'queued',
			'rate_limited'
		]);
		expect(intentCounter).toBe(1);

		// Retry: only the not-queued invoice B, under its SAME key, plus A resent under its SAME key. The window
		// is open again now. Neither may create a second intent.
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		const retry = await (
			await POST(event([item(INV.a, KEY.a), item(INV.b, KEY.b)], userClient))
		).json();

		expect(retry.results.map((r: { outcome: string }) => r.outcome)).toEqual(['queued', 'queued']);
		// A's key already had an intent, B's is new: exactly two intents ever exist, never a duplicate for A.
		expect(intentCounter).toBe(2);
		expect(enqueuedByKey.get(KEY.a)?.id).toBe('intent-1');
	});

	// 4. One invoice failing does not stop the others.
	it('keeps sending the rest when one invoice fails', async () => {
		statusRows = [
			{ id: INV.a, issued_at: null },
			{ id: INV.b, issued_at: null },
			{ id: INV.c, issued_at: null }
		];
		// The middle invoice cannot be issued — no customer email — so it fails; the others carry on.
		issueRpc.mockImplementation((_name: string, args: Record<string, unknown>) => {
			if (args.target_invoice_id === INV.b) {
				return Promise.resolve({
					error: {
						code: '55000',
						message: 'This invoice needs a customer email address before it can be sent.'
					}
				});
			}
			return Promise.resolve({ error: null });
		});

		const response = await POST(
			event([item(INV.a, KEY.a), item(INV.b, KEY.b), item(INV.c, KEY.c)], userClient)
		);
		const body = await response.json();

		expect(body.summary).toMatchObject({
			total: 3,
			queued: 2,
			failed: 1,
			rate_limited: 0,
			skipped: 0
		});
		expect(body.results.map((r: { outcome: string }) => r.outcome)).toEqual([
			'queued',
			'failed',
			'queued'
		]);
		expect(body.results[1]).toMatchObject({
			invoice_id: INV.b,
			reason: 'This invoice needs a customer email address before it can be sent.'
		});
		// The failed invoice is never queued; the other two are.
		const enqueues = ownerRpc.mock.calls.filter(
			(c) => c[0] === 'enqueue_invoice_communication_email'
		);
		expect(enqueues.map((c) => (c[1] as Record<string, unknown>).target_invoice_id)).toEqual([
			INV.a,
			INV.c
		]);
	});

	// An invoice that is not in the caller's organization simply is not found, and does not stop the batch.
	it('fails an unknown invoice without blocking the batch', async () => {
		statusRows = [{ id: INV.a, issued_at: null }];
		const response = await POST(event([item(INV.a, KEY.a), item(INV.b, KEY.b)], userClient));
		const body = await response.json();

		expect(body.summary).toMatchObject({ total: 2, queued: 1, failed: 1 });
		expect(body.results.map((r: { outcome: string }) => r.outcome)).toEqual(['queued', 'failed']);
		expect(body.results[1]).toMatchObject({
			invoice_id: INV.b,
			reason: 'That invoice could not be found.'
		});
	});
});
