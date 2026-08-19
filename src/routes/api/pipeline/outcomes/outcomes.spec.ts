import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHasPermission = vi.mocked(hasPermission);

const organizationId = '00000000-0000-4000-8000-0000000000aa';
const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

function outcomeRow(overrides: Record<string, unknown> = {}) {
	return {
		id: 'opp-1',
		title: 'Rewire the panel',
		outcome: 'lost',
		created_at: '2026-08-01T00:00:00.000Z',
		outcome_at: '2026-08-10T00:00:00.000Z',
		client_id: 'client-1',
		client_display_name: 'Ada Lovelace',
		client_company_name: null,
		estimated_value: null,
		...overrides
	};
}

function event(url: string, rows: unknown[] = []) {
	const rpc = vi.fn().mockResolvedValue({ data: rows, error: null });
	return {
		url: new URL(url),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

describe('sales outcomes report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	it('needs pipeline.view', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);

		const response = await GET(event('http://localhost/api/pipeline/outcomes?type=lost'));
		expect(response.status).toBe(403);
	});

	it('rejects a missing or invalid type', async () => {
		const response = await GET(event('http://localhost/api/pipeline/outcomes'));
		expect(response.status).toBe(422);
	});

	it('refuses sorting by total without pipeline.view_value', async () => {
		mockedHasPermission.mockImplementation((_access, permission) => permission !== 'pipeline.view_value');

		const response = await GET(
			event('http://localhost/api/pipeline/outcomes?type=lost&sort=total')
		);
		expect(response.status).toBe(403);
	});

	it('refuses sorting by client without customers.view', async () => {
		mockedHasPermission.mockImplementation((_access, permission) => permission !== 'customers.view');

		const response = await GET(
			event('http://localhost/api/pipeline/outcomes?type=lost&sort=client')
		);
		expect(response.status).toBe(403);
	});

	it('refuses a cursor cut from a different sort', async () => {
		const response = await GET(
			event(
				'http://localhost/api/pipeline/outcomes?type=lost&sort=title&cursor=created:1:2026-08-01T00%3A00%3A00.000Z%7Copp-1'
			)
		);
		expect(response.status).toBe(422);
	});

	it('omits the estimated value entirely without pipeline.view_value', async () => {
		mockedHasPermission.mockReturnValue(false);
		const response = await GET(
			event('http://localhost/api/pipeline/outcomes?type=lost', [
				outcomeRow({ estimated_value: 500 })
			])
		);
		const body = await response.json();

		expect(body.outcomes[0].estimated_value).toBeUndefined();
		expect(body.can_view_value).toBe(false);
	});

	it('masks a client the caller may not see', async () => {
		const response = await GET(
			event('http://localhost/api/pipeline/outcomes?type=lost', [
				outcomeRow({ client_display_name: null, client_company_name: null })
			])
		);
		const body = await response.json();

		expect(body.outcomes[0].client).toBeNull();
	});

	it('reports the last row of a full page as the next cursor', async () => {
		const rows = Array.from({ length: 26 }, (_, index) =>
			outcomeRow({ id: `opp-${index}`, outcome_at: `2026-08-${String(index + 1).padStart(2, '0')}T00:00:00.000Z` })
		);
		const response = await GET(event('http://localhost/api/pipeline/outcomes?type=lost&limit=25', rows));
		const body = await response.json();

		expect(body.outcomes).toHaveLength(25);
		expect(body.next_cursor).toContain('opp-24');
	});

	it('has no next cursor on the last page', async () => {
		const response = await GET(
			event('http://localhost/api/pipeline/outcomes?type=lost', [outcomeRow()])
		);
		const body = await response.json();
		expect(body.next_cursor).toBeNull();
	});

	it('turns a database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });
		const response = await GET({
			url: new URL('http://localhost/api/pipeline/outcomes?type=lost'),
			locals: { supabase: { rpc } }
		} as unknown as Parameters<typeof GET>[0]);
		expect(response.status).toBe(500);
	});
});
