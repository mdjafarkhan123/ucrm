import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as reviewImport } from './+server';
import { requireClientPermission } from '$lib/server/access/clients';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { getObjectBytes } from '$lib/server/storage/r2';

vi.mock('$lib/server/access/clients', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/clients')>(
		'$lib/server/access/clients'
	);
	return { ...actual, requireClientPermission: vi.fn() };
});
vi.mock('$lib/server/security/rate-limit', () => ({
	checkRateLimit: vi.fn(),
	rateLimitedResponse: () => new Response(null, { status: 429 })
}));
vi.mock('$lib/server/storage/r2', () => ({ getObjectBytes: vi.fn() }));

const mockedRequire = vi.mocked(requireClientPermission);
const mockedRateLimit = vi.mocked(checkRateLimit);
const mockedGetBytes = vi.mocked(getObjectBytes);

const ORGANIZATION_ID = 'org-1';
const BATCH_ID = '11111111-1111-4111-8111-111111111111';

function grantAccess() {
	mockedRequire.mockResolvedValue({
		auth: {
			organization: { id: ORGANIZATION_ID, name: 'Bright Spark Electrical', role: 'owner' },
			user: { id: 'user-1', email: 'owner@example.com' }
		},
		access: { permissions: { 'customers.create': true }, features: {} }
	} as never);
}

const CSV = 'First name,Last name,Email\nAda,Lovelace,ada@example.com\n';

const DEFAULT_BATCH = {
	id: BATCH_ID,
	storage_object_key: 'org-1/client-imports/abc.csv',
	column_mapping: {
		'First name': { field: 'first_name' },
		'Last name': { field: 'last_name' },
		Email: { field: 'email' }
	},
	match_action: 'skip',
	status: 'mapped'
};

// Build the POST event: a mocked supabase whose from().select()...maybeSingle() returns the batch and whose
// .rpc() stands in for match_import_clients + review_import_batch.
function reviewEvent(
	options: {
		batch?: unknown;
		batchError?: unknown;
		matchResult?: { data: unknown; error: unknown };
		reviewResult?: { data: unknown; error: unknown };
	} = {}
) {
	const {
		batch = DEFAULT_BATCH,
		batchError = null,
		matchResult = { data: [], error: null },
		reviewResult = { data: { id: BATCH_ID, status: 'reviewed' }, error: null }
	} = options;

	const maybeSingle = vi.fn(() => Promise.resolve({ data: batch, error: batchError }));
	const eq2 = vi.fn(() => ({ maybeSingle }));
	const eq1 = vi.fn(() => ({ eq: eq2 }));
	const select = vi.fn(() => ({ eq: eq1 }));
	const from = vi.fn(() => ({ select }));

	const rpc = vi.fn((name: string) =>
		Promise.resolve(name === 'match_import_clients' ? matchResult : reviewResult)
	);

	return {
		request: new Request(`http://localhost/api/imports/clients/${BATCH_ID}/review`, {
			method: 'POST'
		}),
		params: { batchId: BATCH_ID },
		locals: { supabase: { from, rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof reviewImport>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

beforeEach(() => {
	vi.clearAllMocks();
	grantAccess();
	mockedRateLimit.mockResolvedValue({ allowed: true } as never);
	mockedGetBytes.mockResolvedValue(new TextEncoder().encode(CSV));
});

describe('POST /api/imports/clients/[batchId]/review', () => {
	it('returns the guard response when the caller lacks customers.create', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const event = reviewEvent();
		const response = await reviewImport(event);
		expect(response.status).toBe(403);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects when the rate limit is exceeded', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 } as never);
		const response = await reviewImport(reviewEvent());
		expect(response.status).toBe(429);
	});

	it('404s when the batch is not found', async () => {
		const response = await reviewImport(reviewEvent({ batch: null }));
		expect(response.status).toBe(404);
	});

	it('422s when the batch is no longer reviewable', async () => {
		const response = await reviewImport(
			reviewEvent({ batch: { ...DEFAULT_BATCH, status: 'importing' } })
		);
		expect(response.status).toBe(422);
	});

	it('503s when the file cannot be re-opened', async () => {
		mockedGetBytes.mockRejectedValue(new Error('gone'));
		const response = await reviewImport(reviewEvent());
		expect(response.status).toBe(503);
	});

	it('reviews the file, persists the dry-run, and returns a summary', async () => {
		const event = reviewEvent();
		const response = await reviewImport(event);
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body).toMatchObject({ batch_id: BATCH_ID, status: 'reviewed' });
		expect(body.summary).toMatchObject({ total: 1, create: 1 });

		const calls = event.__rpc.mock.calls.map((call) => call[0]);
		expect(calls).toContain('match_import_clients');
		expect(calls).toContain('review_import_batch');

		const reviewCall = event.__rpc.mock.calls.find((call) => call[0] === 'review_import_batch');
		expect(reviewCall?.[1].payload.batch_id).toBe(BATCH_ID);
		expect(reviewCall?.[1].payload.rows[0].planned_action).toBe('create');
	});

	it('skips the dedupe lookup when the file has no email or phone columns', async () => {
		const event = reviewEvent({
			batch: {
				...DEFAULT_BATCH,
				column_mapping: {
					'First name': { field: 'first_name' },
					'Last name': { field: 'last_name' }
				}
			}
		});
		mockedGetBytes.mockResolvedValue(
			new TextEncoder().encode('First name,Last name\nAda,Lovelace\n')
		);
		await reviewImport(event);
		const calls = event.__rpc.mock.calls.map((call) => call[0]);
		expect(calls).not.toContain('match_import_clients');
		expect(calls).toContain('review_import_batch');
	});

	it('maps a missing batch in the write RPC (P0002) to a 404', async () => {
		const response = await reviewImport(
			reviewEvent({ reviewResult: { data: null, error: { code: 'P0002' } } })
		);
		expect(response.status).toBe(404);
	});

	it('maps a frozen batch in the write RPC (22023) to a 422', async () => {
		const response = await reviewImport(
			reviewEvent({ reviewResult: { data: null, error: { code: '22023' } } })
		);
		expect(response.status).toBe(422);
	});
});
