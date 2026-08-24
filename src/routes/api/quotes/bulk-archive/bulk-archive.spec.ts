import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as bulkArchive } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

// One outcome per id, read in call order, so a test can hand each selected quote its own answer without
// caring which batch of ten it lands in.
function bulkEvent(body: unknown, outcomes: Array<{ data: unknown; error: unknown }> = []) {
	let call = 0;
	const rpc = vi.fn(() =>
		Promise.resolve(outcomes[call++] ?? { data: { applied: true }, error: null })
	);
	return {
		request: new Request('http://localhost/api/quotes/bulk-archive', {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof bulkArchive>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

describe('bulk archive quotes', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = bulkEvent({ ids: [id(1)] });

		expect((await bulkArchive(target)).status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('refuses a body that is not valid JSON', async () => {
		const target = {
			request: new Request('http://localhost/api/quotes/bulk-archive', {
				method: 'POST',
				body: '{not json'
			}),
			locals: { supabase: { rpc: vi.fn() } }
		} as unknown as Parameters<typeof bulkArchive>[0];

		expect((await bulkArchive(target)).status).toBe(422);
	});

	it('refuses an empty selection before touching the database', async () => {
		const target = bulkEvent({ ids: [] });

		expect((await bulkArchive(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('archives what it can and reports how many it skipped', async () => {
		const target = bulkEvent({ ids: [id(1), id(2)] }, [
			{ data: { applied: true, status: 'archived' }, error: null },
			{ data: { applied: false }, error: { code: '23514', message: 'Converted quotes stay put.' } }
		]);

		const response = await bulkArchive(target);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ archived: 1, skipped: 1 });
		expect(target.__rpc).toHaveBeenCalledTimes(2);
		expect(target.__rpc).toHaveBeenCalledWith('archive_quote', {
			target_quote_id: id(1),
			reason: null
		});
	});

	it('does not let one failed row abort the rest of the batch', async () => {
		const target = bulkEvent({ ids: [id(1), id(2), id(3)] }, [
			{ data: null, error: { code: '23514', message: 'nope' } },
			{ data: { applied: true }, error: null },
			{ data: { applied: true }, error: null }
		]);

		const response = await bulkArchive(target);

		expect(await response.json()).toEqual({ archived: 2, skipped: 1 });
	});

	it('processes a selection larger than one concurrency batch', async () => {
		const ids = Array.from({ length: 12 }, (_, index) => id(index + 1));
		const target = bulkEvent(
			{ ids },
			ids.map(() => ({ data: { applied: true }, error: null }))
		);

		const response = await bulkArchive(target);

		expect(target.__rpc).toHaveBeenCalledTimes(12);
		expect(await response.json()).toEqual({ archived: 12, skipped: 0 });
	});
});
