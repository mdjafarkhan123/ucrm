import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as commitImport } from './+server';
import { requireClientPermission } from '$lib/server/access/clients';

vi.mock('$lib/server/access/clients', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/clients')>(
		'$lib/server/access/clients'
	);
	return { ...actual, requireClientPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireClientPermission);

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

// Build the POST event the route reads: a JSON body with the consent flag, the batch id in the path params,
// and a mocked supabase.rpc that stands in for commit_import_batch.
function commitEvent(
	body: unknown,
	rpcResult: { data: unknown; error: unknown } = {
		data: {
			id: BATCH_ID,
			status: 'importing',
			created_count: 0,
			updated_count: 0,
			skipped_count: 2,
			held_count: 1,
			error_count: 3
		},
		error: null
	}
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		request: new Request(`http://localhost/api/imports/clients/${BATCH_ID}/commit`, {
			method: 'POST',
			body: typeof body === 'string' ? body : JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		params: { batchId: BATCH_ID },
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof commitImport>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

beforeEach(() => {
	vi.clearAllMocks();
	grantAccess();
});

describe('POST /api/imports/clients/[batchId]/commit', () => {
	it('returns the guard response when the caller lacks customers.create', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const event = commitEvent({ consent_affirmed: true });
		const response = await commitImport(event);
		expect(response.status).toBe(403);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not JSON', async () => {
		const event = commitEvent('not json at all');
		const response = await commitImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects a missing consent flag before reaching the database', async () => {
		const event = commitEvent({});
		const response = await commitImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects an unaffirmed consent flag before reaching the database', async () => {
		const event = commitEvent({ consent_affirmed: false });
		const response = await commitImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('commits an affirmed batch and returns its status and counts', async () => {
		const event = commitEvent({ consent_affirmed: true });
		const response = await commitImport(event);

		expect(response.status).toBe(200);
		const responseBody = await response.json();
		expect(responseBody).toEqual({
			batch_id: BATCH_ID,
			status: 'importing',
			counts: { created: 0, updated: 0, skipped: 2, held: 1, error: 3 }
		});

		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('commit_import_batch');
		expect(args.payload).toEqual({ batch_id: BATCH_ID, consent_affirmed: true });
	});

	it('maps a missing batch (P0002) to a 404', async () => {
		const event = commitEvent({ consent_affirmed: true }, { data: null, error: { code: 'P0002' } });
		const response = await commitImport(event);
		expect(response.status).toBe(404);
	});

	it('maps a permission failure (42501) to a 403', async () => {
		const event = commitEvent({ consent_affirmed: true }, { data: null, error: { code: '42501' } });
		const response = await commitImport(event);
		expect(response.status).toBe(403);
	});

	it('maps the consent backstop (23514) to a 422 on the consent field', async () => {
		const event = commitEvent({ consent_affirmed: true }, { data: null, error: { code: '23514' } });
		const response = await commitImport(event);
		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors?.consent_affirmed).toBeTruthy();
	});

	it('maps a non-reviewed batch (22023) to a 422', async () => {
		const event = commitEvent({ consent_affirmed: true }, { data: null, error: { code: '22023' } });
		const response = await commitImport(event);
		expect(response.status).toBe(422);
	});

	it('maps an unexpected database error to a 500', async () => {
		const event = commitEvent(
			{ consent_affirmed: true },
			{ data: null, error: { code: '08006', message: 'connection failure' } }
		);
		const response = await commitImport(event);
		expect(response.status).toBe(500);
	});
});
