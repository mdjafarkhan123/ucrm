import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH as mapImport } from './+server';
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

// Build the PATCH event the route reads: a JSON body with the mapping, the batch id in the path params, and a
// mocked supabase.rpc that stands in for set_import_batch_mapping.
function mapEvent(
	body: unknown,
	rpcResult: { data: unknown; error: unknown } = {
		data: { id: BATCH_ID, status: 'mapped' },
		error: null
	}
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		request: new Request(`http://localhost/api/imports/clients/${BATCH_ID}`, {
			method: 'PATCH',
			body: typeof body === 'string' ? body : JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		params: { batchId: BATCH_ID },
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof mapImport>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const validBody = {
	match_action: 'skip',
	column_mapping: {
		'First name': { field: 'first_name' },
		Email: { field: 'email' }
	}
};

beforeEach(() => {
	vi.clearAllMocks();
	grantAccess();
});

describe('PATCH /api/imports/clients/[batchId]', () => {
	it('returns the guard response when the caller lacks customers.create', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const event = mapEvent(validBody);
		const response = await mapImport(event);
		expect(response.status).toBe(403);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not JSON', async () => {
		const event = mapEvent('not json at all');
		const response = await mapImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects an empty mapping', async () => {
		const event = mapEvent({ match_action: 'skip', column_mapping: {} });
		const response = await mapImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects a column mapped to an unknown field', async () => {
		const event = mapEvent({
			match_action: 'skip',
			column_mapping: { Nickname: { field: 'not_a_real_field' } }
		});
		const response = await mapImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects two columns mapped to the same field', async () => {
		const event = mapEvent({
			match_action: 'skip',
			column_mapping: {
				Email: { field: 'email' },
				'Work email': { field: 'email' }
			}
		});
		const response = await mapImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects an invalid match action', async () => {
		const event = mapEvent({
			match_action: 'overwrite_everything',
			column_mapping: { Email: { field: 'email' } }
		});
		const response = await mapImport(event);
		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('saves the mapping, defaulting dont_overwrite to false, and returns the mapped batch', async () => {
		const event = mapEvent(validBody);
		const response = await mapImport(event);

		expect(response.status).toBe(200);
		const responseBody = await response.json();
		expect(responseBody).toEqual({ batch_id: BATCH_ID, status: 'mapped' });

		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('set_import_batch_mapping');
		expect(args.payload).toEqual({
			batch_id: BATCH_ID,
			match_action: 'skip',
			column_mapping: {
				'First name': { field: 'first_name', dont_overwrite: false },
				Email: { field: 'email', dont_overwrite: false }
			}
		});
	});

	it('keeps an explicit dont_overwrite toggle', async () => {
		const event = mapEvent({
			match_action: 'update',
			column_mapping: { Phone: { field: 'phone', dont_overwrite: true } }
		});
		const response = await mapImport(event);
		expect(response.status).toBe(200);
		const [, args] = event.__rpc.mock.calls[0];
		expect(args.payload.column_mapping.Phone).toEqual({ field: 'phone', dont_overwrite: true });
	});

	it('maps a missing batch (P0002) to a 404', async () => {
		const event = mapEvent(validBody, { data: null, error: { code: 'P0002' } });
		const response = await mapImport(event);
		expect(response.status).toBe(404);
	});

	it('maps a permission failure (42501) to a 403', async () => {
		const event = mapEvent(validBody, { data: null, error: { code: '42501' } });
		const response = await mapImport(event);
		expect(response.status).toBe(403);
	});

	it('maps a frozen batch (22023) to a 422', async () => {
		const event = mapEvent(validBody, { data: null, error: { code: '22023' } });
		const response = await mapImport(event);
		expect(response.status).toBe(422);
	});

	it('maps any other database error to a 500', async () => {
		const event = mapEvent(validBody, { data: null, error: { code: '08006' } });
		const response = await mapImport(event);
		expect(response.status).toBe(500);
	});
});
