import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { GET as COUNTS } from './counts/+server';
import { GET as DETAIL, PATCH } from './[id]/+server';
import { POST as ADD_VISITS } from './[id]/visits/+server';
import { PATCH as UPDATE_VISIT, DELETE as DELETE_VISIT } from './[id]/visits/[visitId]/+server';
import { POST as MOVE_VISITS } from './[id]/visits/bulk-move/+server';
import { POST as RESCHEDULE } from './[id]/schedule/+server';
import { POST as APPLY_FUTURE } from './[id]/visits/[visitId]/apply-to-future/+server';
import { POST as PREVIEW_RECURRENCE } from './recurrence-preview/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { requireOrganization } from '$lib/server/auth/organization';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

vi.mock('$lib/server/auth/organization', () => ({
	requireOrganization: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedRequireOrg = vi.mocked(requireOrganization);
const clientId = '00000000-0000-4000-8000-000000000081';
const propertyId = '00000000-0000-4000-8000-000000000082';

// PostgREST's builder is a chain that resolves on await, so the stub records what was asked for and
// answers the same result however the route finishes the call.
function builder(result: unknown) {
	const calls: Array<{ method: string; args: unknown[] }> = [];
	const chain: Record<string | symbol, unknown> = new Proxy(
		{},
		{
			get(_target, property) {
				if (property === '__calls') return calls;
				if (property === 'then')
					return (...args: unknown[]) =>
						(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(
							...args
						);
				return (...args: unknown[]) => {
					calls.push({ method: String(property), args });
					return chain;
				};
			}
		}
	);
	return chain;
}

const rows = [
	{
		id: 'job-1',
		job_number: 2,
		title: 'Panel upgrade',
		job_type: 'one_off',
		is_as_needed: false,
		status: 'active',
		derived_status: 'unscheduled',
		currency_code: 'USD',
		created_at: '2026-09-01T10:00:00Z',
		contract_start_date: null,
		contract_end_date: null,
		quote_id: null,
		client_id: clientId,
		client_display_name: 'Abbas Uddin',
		client_company_name: null,
		property_id: propertyId,
		property_label: 'Home',
		property_address_line1: '12 Mill Road',
		property_city: 'Savar',
		property_state_region: null,
		property_postal_code: null
	}
];

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.jobs': true } }
	} as never;
}

const DEFAULT_MONEY = { 'job-1': { total_minor: 60000 } };

function listEvent(
	url: string,
	result: unknown = { data: rows, error: null },
	money: unknown = DEFAULT_MONEY
) {
	const chain = builder(result);
	const rpc = vi.fn(() => Promise.resolve({ data: money, error: null }));
	return {
		url: new URL(`http://localhost/api/jobs${url}`),
		locals: { supabase: { from: vi.fn(() => chain), rpc } },
		__chain: chain as unknown as { __calls: Array<{ method: string; args: unknown[] }> },
		__rpc: rpc
	} as unknown as Parameters<typeof GET>[0] & {
		__chain: { __calls: Array<{ method: string; args: unknown[] }> };
		__rpc: ReturnType<typeof vi.fn>;
	};
}

function calls(event: { __chain: { __calls: Array<{ method: string; args: unknown[] }> } }) {
	return event.__chain.__calls;
}

describe('job list API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.view_price': true }));
	});

	it('returns the permission check response without reading anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = listEvent('');

		const response = await GET(target);

		expect(response.status).toBe(403);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('reads the derived status from the database rather than working it out here', async () => {
		const target = listEvent('');

		const body = await (await GET(target)).json();
		const source = calls(target).find((call) => call.method === 'select');

		expect(target.locals.supabase.from).toHaveBeenCalledWith('job_list_rows');
		expect(String(source?.args[0])).toContain('derived_status');
		expect(body.jobs[0].derived_status).toBe('unscheduled');
	});

	it('shows open work by default, which is also the filter the partial index is built for', async () => {
		const target = listEvent('');

		await GET(target);
		const stored = calls(target).find((call) => call.method === 'eq' && call.args[0] === 'status');

		expect(stored?.args[1]).toBe('active');
		expect(calls(target).some((call) => call.method === 'in')).toBe(false);
	});

	it('asks for exactly the derived statuses the filter names', async () => {
		const target = listEvent('?status=ending_soon,archived');

		await GET(target);
		const filter = calls(target).find(
			(call) => call.method === 'in' && call.args[0] === 'derived_status'
		);

		expect(filter?.args[1]).toEqual(['ending_soon', 'archived']);
		expect(calls(target).some((call) => call.method === 'eq' && call.args[0] === 'status')).toBe(
			false
		);
	});

	it('ignores a status nobody defined instead of filtering on it', async () => {
		const target = listEvent('?status=invented');

		await GET(target);

		expect(
			calls(target).some((call) => call.method === 'in' && call.args[0] === 'derived_status')
		).toBe(false);
	});

	it('filters by job type when asked', async () => {
		const target = listEvent('?type=recurring');

		await GET(target);
		const filter = calls(target).find(
			(call) => call.method === 'in' && call.args[0] === 'job_type'
		);

		expect(filter?.args[1]).toEqual(['recurring']);
	});

	it('never asks for the total when the member may not see money', async () => {
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.view_price': false }));
		const target = listEvent('');

		const body = await (await GET(target)).json();
		const source = calls(target).find((call) => call.method === 'select');

		expect(String(source?.args[0])).not.toContain('total_minor');
		expect(target.__rpc).not.toHaveBeenCalled();
		expect(body.jobs[0].total_minor).toBeNull();
	});

	it('asks for the page’s totals in one gated call', async () => {
		const target = listEvent('');

		const body = await (await GET(target)).json();

		expect(target.__rpc).toHaveBeenCalledWith('job_money', { target_job_ids: ['job-1'] });
		expect(body.jobs[0].total_minor).toBe(60000);
	});

	it('pages by seeking to the cursor instead of counting past it', async () => {
		const target = listEvent('?cursor=2026-09-01T10:00:00Z|job-1');

		await GET(target);
		const seek = calls(target).find((call) => call.method === 'lte');

		expect(seek?.args[0]).toBe('created_at');
		expect(calls(target).some((call) => call.method === 'range')).toBe(false);
	});

	it('hands back a cursor only when another page exists', async () => {
		const single = await (await GET(listEvent(''))).json();
		expect(single.next_cursor).toBeNull();

		const full = listEvent(
			'?limit=1',
			{ data: [rows[0], { ...rows[0], id: 'job-2', job_number: 3 }], error: null },
			DEFAULT_MONEY
		);
		const paged = await (await GET(full)).json();

		expect(paged.jobs).toHaveLength(1);
		expect(paged.next_cursor).toBe('2026-09-01T10:00:00Z|job-1');
	});

	it('sorts by job number when asked, and by nothing else', async () => {
		const target = listEvent('?sort=number&dir=asc');

		await GET(target);
		const order = calls(target).find((call) => call.method === 'order');

		expect(order?.args[0]).toBe('job_number');

		const rejected = await GET(listEvent('?sort=client'));
		expect(rejected.status).toBe(422);
	});

	it('searches a number against the number and a word against the title', async () => {
		const numeric = listEvent('?search=12');
		await GET(numeric);
		expect(String(calls(numeric).find((call) => call.method === 'or')?.args[0])).toContain(
			'job_number.eq.12'
		);

		const word = listEvent('?search=panel');
		await GET(word);
		expect(calls(word).find((call) => call.method === 'ilike')?.args[0]).toBe('title');
	});

	it('reports a database failure instead of drawing an empty list', async () => {
		const target = listEvent('', { data: null, error: { message: 'boom' } });

		const response = await GET(target);

		expect(response.status).toBe(500);
	});
});

describe('create job API', () => {
	const createClientId = '00000000-0000-4000-8000-000000000091';
	const createPropertyId = '00000000-0000-4000-8000-000000000092';
	const idempotencyKey = '00000000-0000-4000-8000-000000000093';

	function createEvent(body: unknown, rpc = vi.fn()) {
		return {
			request: new Request('http://localhost/api/jobs', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}),
			locals: { supabase: { rpc } }
		} as unknown as Parameters<typeof POST>[0];
	}

	const validBody = {
		client_id: createClientId,
		property_id: createPropertyId,
		title: 'Panel upgrade',
		lines: [
			{
				position: 0,
				category: 'service',
				name: 'Labour',
				quantity: 1,
				unit_price_minor: 30000,
				unit_cost_minor: 0
			}
		],
		visits: [{ position: 0, visit_date: '2026-09-10', start_time: '09:00', end_time: '11:00' }],
		idempotency_key: idempotencyKey,
		request_hash: 'v1:total-30000'
	};

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequireOrg.mockResolvedValue({
			organization: { id: 'org-1' },
			user: { id: 'user-1' }
		} as never);
	});

	it('refuses a signed-out caller before touching the database', async () => {
		mockedRequireOrg.mockResolvedValue(null as never);
		const rpc = vi.fn();

		const response = await POST(createEvent(validBody, rpc));

		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body with no client before reaching the database', async () => {
		const rpc = vi.fn();
		const { client_id, ...rest } = validBody;
		void client_id;

		const response = await POST(createEvent(rest, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.client_id).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a job with no visits', async () => {
		const rpc = vi.fn();

		const response = await POST(createEvent({ ...validBody, visits: [] }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.visits).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('hands the whole command to the database and answers 201', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { applied: true, job_id: 'job-1', job_number: 9, visit_count: 1, line_count: 1 },
			error: null
		});

		const response = await POST(createEvent(validBody, rpc));

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('create_job_with_visits', {
			target_organization_id: 'org-1',
			target_client_id: createClientId,
			target_property_id: createPropertyId,
			new_title: 'Panel upgrade',
			new_instructions: null,
			invoice_on_close: true,
			scope_lines: expect.arrayContaining([expect.objectContaining({ name: 'Labour' })]),
			visits: expect.arrayContaining([expect.objectContaining({ visit_date: '2026-09-10' })]),
			new_idempotency_key: idempotencyKey,
			new_request_hash: 'v1:total-30000',
			new_job_type: 'one_off',
			new_is_as_needed: false,
			new_recurrence: null
		});
		await expect(response.json()).resolves.toMatchObject({ job_number: 9 });
	});

	// --- Recurring and as-needed jobs (Part 10) ---------------------------------------------------------

	const weeklyRule = {
		frequency: 'weekly',
		interval_count: 1,
		weekdays: [1],
		start_date: '2026-09-07',
		end_mode: 'after',
		duration_count: 6,
		duration_unit: 'month'
	};

	const recurringBody = {
		...validBody,
		job_type: 'recurring',
		visits: [],
		recurrence: weeklyRule
	};

	it('sends a recurring job as a rule with no visits', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { applied: true, job_id: 'job-9', job_number: 9, visit_count: 26 },
			error: null
		});

		const response = await POST(createEvent(recurringBody, rpc));

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith(
			'create_job_with_visits',
			expect.objectContaining({
				new_job_type: 'recurring',
				new_is_as_needed: false,
				visits: [],
				new_recurrence: expect.objectContaining({ frequency: 'weekly', weekdays: [1] })
			})
		);
	});

	it('sends an as-needed job with neither a rule nor visits', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { applied: true, job_id: 'job-10', job_number: 10, visit_count: 0 },
			error: null
		});

		const { recurrence, ...rest } = recurringBody;
		void recurrence;
		const response = await POST(createEvent({ ...rest, is_as_needed: true }, rpc));

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith(
			'create_job_with_visits',
			expect.objectContaining({
				new_job_type: 'recurring',
				new_is_as_needed: true,
				new_recurrence: null,
				visits: []
			})
		);
	});

	it('refuses a recurring job with no schedule', async () => {
		const rpc = vi.fn();
		const { recurrence, ...rest } = recurringBody;
		void recurrence;

		const response = await POST(createEvent(rest, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a weekly schedule that names no day', async () => {
		const rpc = vi.fn();

		const response = await POST(
			createEvent({ ...recurringBody, recurrence: { ...weeklyRule, weekdays: [] } }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors['recurrence.weekdays']).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a one-off job that carries a repeat rule', async () => {
		const rpc = vi.fn();

		const response = await POST(
			createEvent({ ...validBody, job_type: 'one_off', recurrence: weeklyRule }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses an as-needed job that also lists visits', async () => {
		const rpc = vi.fn();

		const response = await POST(
			createEvent({ ...validBody, job_type: 'recurring', is_as_needed: true }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('reports the same key with different details as a conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'That job was already started with different details.' }
		});

		const response = await POST(createEvent(validBody, rpc));

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'already_started' });
	});

	it('turns a refused create into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23503', message: 'That property is not this client’s.' }
		});

		const response = await POST(createEvent(validBody, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.form).toBe('That property is not this client’s.');
	});

	it('answers a client or property it cannot see the same way as one that does not exist', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		const response = await POST(createEvent(validBody, rpc));

		expect(response.status).toBe(404);
	});
});

describe('job overview counts', () => {
	function countsEvent(result: unknown) {
		const rpc = vi.fn(() => Promise.resolve(result));
		return {
			url: new URL('http://localhost/api/jobs/counts'),
			locals: {
				supabase: {
					rpc,
					from: vi.fn(() => builder({ data: null, error: null }))
				}
			},
			__rpc: rpc
		} as unknown as Parameters<typeof COUNTS>[0] & { __rpc: ReturnType<typeof vi.fn> };
	}

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true }));
	});

	it('fills in a zero for every status the database did not return', async () => {
		const target = countsEvent({
			data: [{ derived_status: 'unscheduled', total: 3 }],
			error: null
		});

		const body = await (await COUNTS(target)).json();

		expect(body.counts.unscheduled).toBe(3);
		expect(body.counts.late).toBe(0);
		expect(body.counts.requires_invoicing).toBe(0);
		expect(body.counts.archived).toBe(0);
	});

	it('refuses a member without jobs.view', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);

		const response = await COUNTS(countsEvent({ data: [], error: null }));

		expect(response.status).toBe(403);
	});
});

describe('job detail API', () => {
	const detailRow = {
		id: 'job-1',
		job_number: 2,
		title: 'Panel upgrade',
		job_type: 'one_off',
		is_as_needed: false,
		status: 'active',
		derived_status: 'unscheduled',
		price_basis: 'job_total',
		billing_timing: 'on_closure',
		currency_code: 'USD',
		contract_start_date: null,
		contract_end_date: null,
		quote_id: null,
		created_at: '2026-09-01T10:00:00Z',
		client_id: clientId,
		client_display_name: 'Abbas Uddin',
		client_company_name: null,
		property_id: propertyId,
		property_label: 'Home',
		property_address_line1: '12 Mill Road',
		property_city: 'Savar',
		property_state_region: null,
		property_postal_code: null
	};
	const extraRow = {
		instructions: 'Bring the tall ladder.',
		revision: 3,
		client: {
			contact_methods: [
				{ kind: 'email', value: 'abbas@example.com', is_primary: true },
				{ kind: 'phone', value: '01700000000', is_primary: true }
			]
		},
		property: { address_line2: 'Flat 2' }
	};

	// Each table the detail read touches gets its own answer, so the seven-way Promise.all resolves the shape
	// the route expects per table rather than one result standing in for all of them. `job_money` and
	// `job_line_money` answer their own keyed shapes so the stitched lines carry the right per-line numbers.
	function detailEvent(results: Record<string, unknown> = {}, money: unknown = undefined) {
		const table = (name: string, fallback: unknown) =>
			builder(name in results ? results[name] : fallback);
		const rpc = vi.fn((name: string) =>
			Promise.resolve({
				data:
					name === 'job_line_money'
						? { 'line-1': { unit_price_minor: 30000, line_total_minor: 30000 } }
						: (money ?? { 'job-1': { subtotal_minor: 50000, total_minor: 60000 } }),
				error: null
			})
		);
		const from = vi.fn((name: string) => {
			if (name === 'job_list_rows') return table(name, { data: detailRow, error: null });
			if (name === 'jobs') return table(name, { data: extraRow, error: null });
			if (name === 'job_line_items') return table(name, { data: [], error: null });
			if (name === 'job_visits') return table(name, { data: [], error: null });
			if (name === 'organization_settings')
				return table(name, {
					data: { timezone: 'UTC', currency_code: 'USD', locale: 'en-GB' },
					error: null
				});
			return table(name, { data: null, error: null });
		});
		return {
			params: { id: 'job-1' },
			locals: { supabase: { from, rpc } },
			__rpc: rpc
		} as unknown as Parameters<typeof DETAIL>[0] & { __rpc: ReturnType<typeof vi.fn> };
	}

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(
			context({ 'jobs.view': true, 'jobs.view_price': true, 'jobs.edit': true })
		);
	});

	it('reports a job it cannot find as not found', async () => {
		const response = await DETAIL(detailEvent({ job_list_rows: { data: null, error: null } }));

		expect(response.status).toBe(404);
	});

	it('returns the job with its instructions, money and edit right', async () => {
		const target = detailEvent();

		const body = await (await DETAIL(target)).json();

		expect(body.job.id).toBe('job-1');
		expect(body.job.instructions).toBe('Bring the tall ladder.');
		expect(body.job.revision).toBe(3);
		expect(body.job.client.email).toBe('abbas@example.com');
		expect(body.money.total_minor).toBe(60000);
		expect(body.can_edit).toBe(true);
	});

	it('withholds the money from a member who may not see prices', async () => {
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.view_price': false }));
		const target = detailEvent();

		const body = await (await DETAIL(target)).json();

		expect(target.__rpc).not.toHaveBeenCalledWith('job_money', expect.anything());
		expect(body.money).toBeNull();
		expect(body.can_edit).toBe(false);
	});

	it('reads a line’s own name straight off the row but its money from the gated call', async () => {
		const target = detailEvent({
			job_line_items: {
				data: [
					{
						id: 'line-1',
						position: 0,
						source_catalog_item_id: null,
						line_kind: 'priced',
						category: 'service',
						is_labor: true,
						name: 'Labour',
						description: null,
						unit_label: null,
						quantity: 1,
						is_taxable: true,
						image_attachment_id: null
					}
				],
				error: null
			}
		});

		const body = await (await DETAIL(target)).json();

		expect(target.__rpc).toHaveBeenCalledWith('job_line_money', { target_job_id: 'job-1' });
		expect(body.lines[0].name).toBe('Labour');
		expect(body.lines[0].unit_price_minor).toBe(30000);
		expect(body.lines[0].line_total_minor).toBe(30000);
	});

	it('never asks for a line’s money for a member who may not see prices', async () => {
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.view_price': false }));
		const target = detailEvent({
			job_line_items: {
				data: [
					{
						id: 'line-1',
						position: 0,
						source_catalog_item_id: null,
						line_kind: 'priced',
						category: 'service',
						is_labor: true,
						name: 'Labour',
						description: null,
						unit_label: null,
						quantity: 1,
						is_taxable: true,
						image_attachment_id: null
					}
				],
				error: null
			}
		});

		const body = await (await DETAIL(target)).json();

		expect(target.__rpc).not.toHaveBeenCalledWith('job_line_money', expect.anything());
		expect(body.lines[0].unit_price_minor ?? null).toBeNull();
	});

	it('maps a visit’s assignees to a list of ids', async () => {
		const target = detailEvent({
			job_visits: {
				data: [
					{
						id: 'visit-1',
						position: 0,
						visit_date: '2026-09-10',
						start_time: '09:00',
						end_time: '11:00',
						all_day: false,
						title: null,
						instructions: null,
						completed_at: null,
						assignments: [{ user_id: 'user-9' }, { user_id: 'user-10' }]
					}
				],
				error: null
			}
		});

		const body = await (await DETAIL(target)).json();

		expect(body.visits[0].assignee_ids).toEqual(['user-9', 'user-10']);
	});
});

describe('job details edit API', () => {
	function patchEvent(body: unknown, rpc = vi.fn()) {
		return {
			params: { id: 'job-1' },
			request: new Request('http://localhost/api/jobs/job-1', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}),
			locals: { supabase: { rpc } }
		} as unknown as Parameters<typeof PATCH>[0];
	}

	const validBody = { expected_revision: 3, title: 'Panel upgrade v2', instructions: 'New notes' };

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true }));
	});

	it('saves the two fields through the command and returns the new revision', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4 }, error: null });

		const response = await PATCH(patchEvent(validBody, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('update_job_details', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 3,
			new_title: 'Panel upgrade v2',
			new_instructions: 'New notes'
		});
		await expect(response.json()).resolves.toMatchObject({ revision: 4 });
	});

	it('rejects a title that is too short before touching the database', async () => {
		const rpc = vi.fn();

		const response = await PATCH(patchEvent({ ...validBody, title: 'x' }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.title).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('tells the browser to reload when someone else saved first', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'Someone else changed this job. Reload to see the latest.' }
		});

		const response = await PATCH(patchEvent(validBody, rpc));

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
	});

	it('answers a member without jobs.edit the same way as a job that does not exist', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		const response = await PATCH(patchEvent(validBody, rpc));

		expect(response.status).toBe(404);
	});

	it('reports a missing job as not found', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'P0404' } });

		const response = await PATCH(patchEvent(validBody, rpc));

		expect(response.status).toBe(404);
	});
});

describe('job visit scheduling API', () => {
	const visitId = '00000000-0000-4000-8000-000000000101';
	const idempotencyKey = '00000000-0000-4000-8000-000000000102';

	function visitEvent(
		method: string,
		path: string,
		body: unknown,
		rpc = vi.fn(),
		params: Record<string, string> = { id: 'job-1' }
	) {
		return {
			params,
			request: new Request(`http://localhost/api/jobs/job-1${path}`, {
				method,
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}),
			locals: { supabase: { rpc } }
		} as unknown as never;
	}

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true }));
	});

	describe('add visits', () => {
		const validBody = {
			visits: [{ visit_date: '2026-09-10', all_day: true }],
			idempotency_key: idempotencyKey,
			request_hash: 'v1:add'
		};

		it('hands the batch to the command and answers 201', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: { applied: true, added_count: 1, visit_ids: ['visit-1'] },
				error: null
			});

			const response = await ADD_VISITS(visitEvent('POST', '/visits', validBody, rpc) as never);

			expect(response.status).toBe(201);
			expect(rpc).toHaveBeenCalledWith('add_job_visits', {
				target_organization_id: 'org-1',
				target_job_id: 'job-1',
				visits: expect.arrayContaining([expect.objectContaining({ visit_date: '2026-09-10' })]),
				new_idempotency_key: idempotencyKey,
				new_request_hash: 'v1:add'
			});
		});

		it('refuses a member without access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const rpc = vi.fn();

			const response = await ADD_VISITS(visitEvent('POST', '/visits', validBody, rpc) as never);

			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('tells the browser to reload when the idempotency key was reused with different details', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: { code: 'P0409', message: 'Someone else changed this. Reload to see the latest.' }
			});

			const response = await ADD_VISITS(visitEvent('POST', '/visits', validBody, rpc) as never);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
		});

		it('refuses to add visits to a closed job', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: { code: 'P0410', message: 'That job can no longer be changed.' }
			});

			const response = await ADD_VISITS(visitEvent('POST', '/visits', validBody, rpc) as never);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'locked' });
		});
	});

	describe('edit one visit', () => {
		const validBody = {
			expected_revision: 2,
			visit_date: '2026-09-11',
			all_day: true,
			assignee_ids: []
		};

		it('saves the visit through the command and returns the new revision', async () => {
			const rpc = vi.fn().mockResolvedValue({ data: { revision: 3 }, error: null });

			const response = await UPDATE_VISIT(
				visitEvent('PATCH', `/visits/${visitId}`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('update_job_visit', {
				target_organization_id: 'org-1',
				target_job_id: 'job-1',
				target_visit_id: visitId,
				expected_revision: 2,
				new_visit_date: '2026-09-11',
				new_start_time: null,
				new_end_time: null,
				new_all_day: true,
				new_title: null,
				new_instructions: null,
				new_assignee_ids: []
			});
			await expect(response.json()).resolves.toMatchObject({ revision: 3 });
		});

		it('refuses a member without access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const rpc = vi.fn();

			const response = await UPDATE_VISIT(
				visitEvent('PATCH', `/visits/${visitId}`, validBody, rpc, { id: 'job-1', visitId }) as never
			);

			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('tells the browser to reload when someone else changed the visit first', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: {
					code: 'P0409',
					message: 'Someone else changed this visit. Reload to see the latest.'
				}
			});

			const response = await UPDATE_VISIT(
				visitEvent('PATCH', `/visits/${visitId}`, validBody, rpc, { id: 'job-1', visitId }) as never
			);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
		});

		it('refuses to reschedule a completed visit', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: { code: 'P0410', message: 'A completed visit cannot be rescheduled.' }
			});

			const response = await UPDATE_VISIT(
				visitEvent('PATCH', `/visits/${visitId}`, validBody, rpc, { id: 'job-1', visitId }) as never
			);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'locked' });
		});
	});

	describe('delete one visit', () => {
		const validBody = { expected_revision: 2 };

		it('removes the visit through the command', async () => {
			const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });

			const response = await DELETE_VISIT(
				visitEvent('DELETE', `/visits/${visitId}`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('delete_job_visit', {
				target_organization_id: 'org-1',
				target_job_id: 'job-1',
				target_visit_id: visitId,
				expected_revision: 2
			});
		});

		it('refuses a member without access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const rpc = vi.fn();

			const response = await DELETE_VISIT(
				visitEvent('DELETE', `/visits/${visitId}`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('tells the browser to reload when someone else changed the visit first', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: {
					code: 'P0409',
					message: 'Someone else changed this visit. Reload to see the latest.'
				}
			});

			const response = await DELETE_VISIT(
				visitEvent('DELETE', `/visits/${visitId}`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
		});

		it('refuses to remove a completed visit', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: { code: 'P0410', message: 'A completed visit cannot be removed.' }
			});

			const response = await DELETE_VISIT(
				visitEvent('DELETE', `/visits/${visitId}`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'locked' });
		});
	});

	describe('bulk-move visits', () => {
		const validBody = {
			visit_ids: [visitId],
			day_offset: 3,
			idempotency_key: idempotencyKey,
			request_hash: 'v1:move'
		};

		it('hands the batch to the command and reports how many moved', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: { applied: true, moved_count: 1 },
				error: null
			});

			const response = await MOVE_VISITS(
				visitEvent('POST', '/visits/bulk-move', validBody, rpc) as never
			);

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('move_job_visits', {
				target_organization_id: 'org-1',
				target_job_id: 'job-1',
				visit_ids: [visitId],
				day_offset: 3,
				new_idempotency_key: idempotencyKey,
				new_request_hash: 'v1:move'
			});
			await expect(response.json()).resolves.toMatchObject({ moved_count: 1 });
		});

		it('refuses a member without access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const rpc = vi.fn();

			const response = await MOVE_VISITS(
				visitEvent('POST', '/visits/bulk-move', validBody, rpc) as never
			);

			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('tells the browser to reload when the idempotency key was reused with different details', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: { code: 'P0409', message: 'Someone else changed this. Reload to see the latest.' }
			});

			const response = await MOVE_VISITS(
				visitEvent('POST', '/visits/bulk-move', validBody, rpc) as never
			);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
		});

		it('rejects an offset of zero before touching the database', async () => {
			const rpc = vi.fn();

			const response = await MOVE_VISITS(
				visitEvent('POST', '/visits/bulk-move', { ...validBody, day_offset: 0 }, rpc) as never
			);

			expect(response.status).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		});
	});

	describe('edit all visits (reschedule)', () => {
		const rule = {
			frequency: 'weekly',
			interval_count: 1,
			weekdays: [1],
			start_date: '2026-09-07',
			end_mode: 'after',
			duration_count: 6,
			duration_unit: 'month'
		};
		const validBody = {
			expected_revision: 4,
			recurrence: rule,
			idempotency_key: idempotencyKey,
			request_hash: 'v1:reschedule'
		};

		it('replaces the schedule through the command and reports the counts', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: {
					applied: true,
					removed_count: 3,
					created_count: 6,
					completed_kept: 1,
					first_date: '2026-09-07',
					last_date: '2027-03-01',
					revision: 5
				},
				error: null
			});

			const response = await RESCHEDULE(visitEvent('POST', '/schedule', validBody, rpc) as never);

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('reschedule_job_visits', {
				target_organization_id: 'org-1',
				target_job_id: 'job-1',
				expected_revision: 4,
				new_recurrence: expect.objectContaining({ frequency: 'weekly' }),
				new_idempotency_key: idempotencyKey,
				new_request_hash: 'v1:reschedule'
			});
			await expect(response.json()).resolves.toMatchObject({ created_count: 6, removed_count: 3 });
		});

		it('refuses a member without access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const rpc = vi.fn();

			const response = await RESCHEDULE(visitEvent('POST', '/schedule', validBody, rpc) as never);

			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('tells the browser to reload when someone else changed the job first', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: {
					code: 'P0409',
					message: 'Someone else changed this job. Reload to see the latest.'
				}
			});

			const response = await RESCHEDULE(visitEvent('POST', '/schedule', validBody, rpc) as never);

			expect(response.status).toBe(409);
			await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
		});

		it('turns a one-off or as-needed refusal into a form error', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: null,
				error: { code: '23514', message: 'Only a recurring job has a repeating schedule to edit.' }
			});

			const response = await RESCHEDULE(visitEvent('POST', '/schedule', validBody, rpc) as never);

			expect(response.status).toBe(422);
			await expect(response.json()).resolves.toMatchObject({
				field_errors: { form: 'Only a recurring job has a repeating schedule to edit.' }
			});
		});
	});

	describe('apply visit to future', () => {
		const validBody = {
			time_of_day: true,
			assigned_team: false,
			idempotency_key: idempotencyKey,
			request_hash: 'v1:apply'
		};

		it('hands the choice to the command and reports how many took it', async () => {
			const rpc = vi.fn().mockResolvedValue({
				data: { applied: true, updated_count: 4 },
				error: null
			});

			const response = await APPLY_FUTURE(
				visitEvent('POST', `/visits/${visitId}/apply-to-future`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('apply_visit_to_future', {
				target_organization_id: 'org-1',
				target_job_id: 'job-1',
				source_visit_id: visitId,
				copy_time_of_day: true,
				copy_assigned_team: false,
				new_idempotency_key: idempotencyKey,
				new_request_hash: 'v1:apply'
			});
			await expect(response.json()).resolves.toMatchObject({ updated_count: 4 });
		});

		it('refuses a member without access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const rpc = vi.fn();

			const response = await APPLY_FUTURE(
				visitEvent('POST', `/visits/${visitId}/apply-to-future`, validBody, rpc, {
					id: 'job-1',
					visitId
				}) as never
			);

			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('rejects a request that chooses no setting before touching the database', async () => {
			const rpc = vi.fn();

			const response = await APPLY_FUTURE(
				visitEvent(
					'POST',
					`/visits/${visitId}/apply-to-future`,
					{ ...validBody, time_of_day: false, assigned_team: false },
					rpc,
					{ id: 'job-1', visitId }
				) as never
			);

			expect(response.status).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		});
	});
});

describe('recurrence preview API', () => {
	const rule = {
		frequency: 'weekly',
		interval_count: 1,
		weekdays: [1],
		start_date: '2026-09-07',
		end_mode: 'after',
		duration_count: 6,
		duration_unit: 'month'
	};

	function previewEvent(body: unknown, rpc = vi.fn()) {
		return {
			request: new Request('http://localhost/api/jobs/recurrence-preview', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}),
			locals: { supabase: { rpc } }
		} as unknown as Parameters<typeof PREVIEW_RECURRENCE>[0];
	}

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: ['jobs.create'] }
		} as never);
	});

	it('answers with the count and the window the rule covers', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: {
				visit_count: 26,
				first_date: '2026-09-07',
				last_date: '2027-03-01',
				limit: 400,
				over_limit: false
			},
			error: null
		});

		const response = await PREVIEW_RECURRENCE(previewEvent({ recurrence: rule }, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'preview_job_recurrence',
			expect.objectContaining({ rule: expect.objectContaining({ frequency: 'weekly' }) })
		);
		await expect(response.json()).resolves.toMatchObject({ visit_count: 26 });
	});

	it('never stores a per-tenant answer in a shared cache', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { visit_count: 1 }, error: null });

		const response = await PREVIEW_RECURRENCE(previewEvent({ recurrence: rule }, rpc));

		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('rejects a rule the schema cannot read before touching the database', async () => {
		const rpc = vi.fn();

		const response = await PREVIEW_RECURRENCE(
			previewEvent({ recurrence: { ...rule, start_date: 'soon' } }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('turns a schedule the database refuses into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'A repeating schedule cannot run more than ten years.' }
		});

		const response = await PREVIEW_RECURRENCE(previewEvent({ recurrence: rule }, rpc));

		expect(response.status).toBe(422);
		await expect(response.json()).resolves.toMatchObject({
			field_errors: { form: 'A repeating schedule cannot run more than ten years.' }
		});
	});
});
