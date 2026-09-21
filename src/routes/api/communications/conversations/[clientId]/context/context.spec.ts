import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

vi.mock('$lib/server/requests/timezone', () => ({
	organizationFormatting: vi.fn(async () => ({
		ok: true,
		formatting: { timezone: 'UTC', currency_code: 'USD', locale: 'en-GB' }
	}))
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const clientId = '00000000-0000-4000-8000-000000000001';

// One global queue: each `.from(table)` call pops the next result in the order the route issues them --
// matching the `email-history` spec's own convention for a route that fires several reads in one
// `Promise.all`.
function chain(result: { data?: unknown; error?: unknown }) {
	const obj: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'is', 'order', 'limit']) obj[method] = vi.fn(() => obj);
	obj.maybeSingle = vi.fn(() => Promise.resolve(result));
	(obj as { then: unknown }).then = (...args: unknown[]) =>
		(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(...args);
	return obj;
}

function fromQueue(results: Array<{ data?: unknown; error?: unknown }>) {
	const queue = [...results];
	return vi.fn(() => chain(queue.shift() ?? { data: null, error: null }));
}

function event(from: ReturnType<typeof fromQueue>, section?: string) {
	const url = new URL(`http://localhost/api/communications/conversations/${clientId}/context`);
	if (section) url.searchParams.set('section', section);
	return {
		params: { clientId },
		url,
		locals: { supabase: { from } }
	} as unknown as Parameters<typeof GET>[0];
}

function allow(...permissions: string[]) {
	mockedRequire.mockResolvedValue({
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: {
			permissions: Object.fromEntries(['customers.view', ...permissions].map((key) => [key, true])),
			// A permission only counts when the organization's package includes its feature.
			features: { 'core.quotes': true, 'core.jobs': true, 'sales.pipeline': true }
		}
	} as never);
}

const clientRow = {
	id: clientId,
	display_name: 'Acme',
	company_name: 'Acme Co',
	client_type: 'company'
};

describe('reading the conversation context rail', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		allow();
	});

	it('requires customers.view', async () => {
		await GET(event(fromQueue([{ data: clientRow }, { data: [] }])));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'customers.view');
	});

	it('404s when the client is not in this organization (or is deleted)', async () => {
		const response = await GET(event(fromQueue([{ data: null }, { data: [] }])));
		expect(response.status).toBe(404);
	});

	it('500s if either read fails', async () => {
		const response = await GET(
			event(fromQueue([{ data: clientRow }, { error: { message: 'boom' } }]))
		);
		expect(response.status).toBe(500);
	});

	it('returns only the client and folds primary contact methods onto it', async () => {
		const from = fromQueue([
			{ data: clientRow },
			{
				data: [
					{ kind: 'email', value: 'a@example.test' },
					{ kind: 'phone', value: '555-0100' }
				]
			}
		]);
		const response = await GET(event(from));
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.client).toEqual({ ...clientRow, email: 'a@example.test', phone: '555-0100' });
		// Opening a conversation costs two reads, however much work the customer has.
		expect(from).toHaveBeenCalledTimes(2);
	});

	it('lists only the tabs this member may see', async () => {
		allow('quotes.view');
		const response = await GET(event(fromQueue([{ data: clientRow }, { data: [] }])));
		const body = await response.json();
		expect(body.sections).toEqual(['properties', 'requests', 'quotes']);
	});

	it('rejects an unknown section', async () => {
		const response = await GET(event(fromQueue([]), 'payments'));
		expect(response.status).toBe(422);
	});

	it('answers a denied section with nothing, and never reads it', async () => {
		const from = fromQueue([]);
		const response = await GET(event(from, 'jobs'));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ items: [], has_more: false, locale: 'en-GB' });
		expect(from).not.toHaveBeenCalled();
	});

	it('returns a section as the latest few, and says when there are more', async () => {
		const rows = Array.from({ length: 7 }, (_, index) => ({
			id: `req-${index}`,
			title: `Request ${index}`,
			status: 'new',
			created_at: '2026-08-20T00:00:00Z'
		}));
		const response = await GET(event(fromQueue([{ data: rows }]), 'requests'));
		const body = await response.json();
		expect(body.items).toHaveLength(6);
		expect(body.has_more).toBe(true);
		expect(body.locale).toBe('en-GB');
	});

	const jobRow = {
		id: 'job-1',
		job_number: 23,
		title: 'Rewire',
		derived_status: 'upcoming',
		currency_code: 'USD',
		created_at: '2026-08-20T00:00:00Z'
	};

	it('withholds money, and never asks for it, without the price permission', async () => {
		allow('jobs.view');
		const from = fromQueue([{ data: [jobRow] }]);
		const rpc = vi.fn();
		const request = event(from, 'jobs');
		(request.locals.supabase as unknown as { rpc: unknown }).rpc = rpc;
		const body = await (await GET(request)).json();
		expect(body.items[0].total_minor).toBeNull();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('shows money to a member who holds the price permission', async () => {
		allow('jobs.view', 'jobs.view_price');
		const rpc = vi.fn(async () => ({ data: { 'job-1': { total_minor: 132000 } }, error: null }));
		const request = event(fromQueue([{ data: [jobRow] }]), 'jobs');
		(request.locals.supabase as unknown as { rpc: unknown }).rpc = rpc;
		const body = await (await GET(request)).json();
		expect(body.items[0].total_minor).toBe(132000);
		expect(rpc).toHaveBeenCalledWith('job_money', { target_job_ids: ['job-1'] });
	});

	it('reads how a pipeline opportunity ended along with its stage', async () => {
		allow('pipeline.view');
		const row = {
			id: 'op-1',
			title: 'Deal',
			stage: 'request_closed',
			outcome: 'won',
			created_at: 'x'
		};
		const body = await (await GET(event(fromQueue([{ data: [row] }]), 'pipeline'))).json();
		expect(body.items[0]).toMatchObject({ stage: 'request_closed', outcome: 'won' });
	});

	it('500s when a section read fails', async () => {
		const response = await GET(event(fromQueue([{ error: { message: 'boom' } }]), 'requests'));
		expect(response.status).toBe(500);
	});
});
