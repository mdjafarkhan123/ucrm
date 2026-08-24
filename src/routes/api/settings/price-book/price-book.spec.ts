import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as createItem } from './+server';
import { DELETE as deleteItem, PATCH as updateItem } from './[id]/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/access/permission')>()),
	requireOrganizationPermission: vi.fn()
}));

vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedRateLimit = vi.mocked(checkRateLimit);

const context = {
	auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
	access: { permissions: {}, features: {} }
} as never;

function writeEvent(
	body: unknown,
	rpcResult: unknown = {
		data: { id: 'item-1', name: 'Gutter clearing', revision: 1 },
		error: null
	},
	params: Record<string, string> = {}
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		request: new Request('http://localhost/api/settings/price-book', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		params,
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof createItem>[0] &
		Parameters<typeof updateItem>[0] &
		Parameters<typeof deleteItem>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const validCreate = {
	category: 'service',
	name: 'Gutter clearing',
	unit_price_minor: 12500,
	unit_cost_minor: 4000,
	is_taxable: true
};

const validUpdate = { ...validCreate, expected_revision: 1 };

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context);
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('creating a Price Book item', () => {
	it('requires the Owner/Administrator management permission, not the picker permission', async () => {
		await createItem(writeEvent(validCreate));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'settings.price_book.manage');
	});

	it('refuses without the management permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await createItem(writeEvent(validCreate));

		expect(response.status).toBe(403);
	});

	it('calls create_catalog_item scoped to the caller organization', async () => {
		const event = writeEvent(validCreate);
		const response = await createItem(event);

		expect(response.status).toBe(201);
		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('create_catalog_item');
		expect(args).toMatchObject({
			target_organization_id: 'org-1',
			new_name: 'Gutter clearing',
			new_unit_price_minor: 12500,
			new_unit_cost_minor: 4000,
			new_is_taxable: true
		});
	});

	it('rejects a labor item that is not a service before ever calling the database', async () => {
		const event = writeEvent({ category: 'product', name: 'Crew hour', is_labor: true });
		const response = await createItem(event);

		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('waits its turn when the organization is saving too often', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 20 });
		const response = await createItem(writeEvent(validCreate));

		expect(response.status).toBe(429);
	});

	it('turns a duplicate active name into a field error on the name, not a form banner', async () => {
		const response = await createItem(
			writeEvent(validCreate, {
				data: null,
				error: {
					code: '23505',
					message: 'An active Price Book item is already named "Gutter clearing".'
				}
			})
		);
		const body = await response.json();

		expect(response.status).toBe(422);
		expect(body.field_errors.name).toContain('already named');
	});
});

describe('editing a Price Book item', () => {
	it('sends the whole record on its own revision, not a partial patch', async () => {
		const event = writeEvent(validUpdate, undefined, { id: 'item-1' });
		await updateItem(event);

		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('update_catalog_item');
		expect(args).toMatchObject({
			target_organization_id: 'org-1',
			target_item_id: 'item-1',
			expected_revision: 1,
			new_category: 'service',
			new_name: 'Gutter clearing'
		});
	});

	it('turns a stale revision into a conflict', async () => {
		const response = await updateItem(
			writeEvent(
				validUpdate,
				{
					data: null,
					error: {
						code: 'P0409',
						message: 'Someone else changed this item while you were editing.'
					}
				},
				{ id: 'item-1' }
			)
		);
		const body = await response.json();

		expect(response.status).toBe(409);
		expect(body.reason).toBe('stale');
	});

	it('requires expected_revision', async () => {
		const { expected_revision: _unused, ...withoutRevision } = validUpdate;
		const response = await updateItem(writeEvent(withoutRevision, undefined, { id: 'item-1' }));

		expect(response.status).toBe(422);
	});
});

describe('deleting a Price Book item', () => {
	it('sends only the expected revision, deleting permanently rather than archiving', async () => {
		const event = writeEvent(
			{ expected_revision: 1 },
			{ data: { status: 'deleted', id: 'item-1' }, error: null },
			{ id: 'item-1' }
		);
		const response = await deleteItem(event);
		const body = await response.json();

		expect(body.status).toBe('deleted');
		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('delete_catalog_item');
		expect(args).toEqual({
			target_organization_id: 'org-1',
			target_item_id: 'item-1',
			expected_revision: 1
		});
	});

	it('refuses without the management permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await deleteItem(
			writeEvent({ expected_revision: 1 }, undefined, { id: 'item-1' })
		);

		expect(response.status).toBe(403);
	});

	it('turns a stale delete into a conflict rather than removing the wrong version', async () => {
		const response = await deleteItem(
			writeEvent(
				{ expected_revision: 1 },
				{
					data: null,
					error: {
						code: 'P0409',
						message: 'Someone else changed this item while you were editing.'
					}
				},
				{ id: 'item-1' }
			)
		);

		expect(response.status).toBe(409);
	});
});
