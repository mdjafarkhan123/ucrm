import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH as LINES } from './[id]/lines/+server';
import { PATCH as BILLING } from './[id]/billing/+server';
import { PATCH as DISCOUNT } from './[id]/discount/+server';
import { PATCH as TAX } from './[id]/tax/+server';
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
		access: { permissions, features: { 'core.jobs': true } }
	} as never;
}

// Every one of the four is a PATCH on the job with a JSON body, so one event builder covers them all.
function patchEvent(path: string, body: unknown, rpc = vi.fn()) {
	return {
		params: { id: 'job-1' },
		request: new Request(`http://localhost/api/jobs/job-1${path}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as never;
}

const line = {
	position: 0,
	category: 'service',
	is_labor: false,
	source_catalog_item_id: null,
	name: 'Gutter clearing',
	description: null,
	unit_label: null,
	quantity: 2,
	unit_price_minor: 5000,
	unit_cost_minor: 1000,
	is_taxable: true
};

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.edit': true }));
});

describe('job scope API', () => {
	it('hands the whole set to the one command that may write these rows', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4, line_count: 1 }, error: null });

		const response = await LINES(
			patchEvent('/lines', { expected_revision: 3, lines: [line] }, rpc)
		);

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('replace_job_line_items', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 3,
			new_lines: [
				expect.objectContaining({ name: 'Gutter clearing', source_catalog_item_id: null })
			]
		});
		await expect(response.json()).resolves.toMatchObject({ revision: 4, line_count: 1 });
	});

	it('sends the job’s own name for the catalog column, not the quote’s', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4, line_count: 1 }, error: null });
		const catalogId = '00000000-0000-4000-8000-0000000000c1';

		await LINES(
			patchEvent(
				'/lines',
				{
					expected_revision: 3,
					lines: [{ ...line, source_catalog_item_id: catalogId }]
				},
				rpc
			)
		);

		const sent = rpc.mock.calls[0][1].new_lines[0];
		expect(sent.source_catalog_item_id).toBe(catalogId);
		expect(sent).not.toHaveProperty('catalog_item_id');
	});

	it('carries a converted line’s photo through the save instead of dropping it', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4, line_count: 1 }, error: null });
		const attachmentId = '00000000-0000-4000-8000-0000000000a1';

		await LINES(
			patchEvent(
				'/lines',
				{ expected_revision: 3, lines: [{ ...line, image_attachment_id: attachmentId }] },
				rpc
			)
		);

		expect(rpc.mock.calls[0][1].new_lines[0].image_attachment_id).toBe(attachmentId);
	});

	it('rejects a line with no name before touching the database', async () => {
		const rpc = vi.fn();

		const response = await LINES(
			patchEvent('/lines', { expected_revision: 3, lines: [{ ...line, name: '' }] }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses more than a hundred lines without asking the database', async () => {
		const rpc = vi.fn();

		const response = await LINES(
			patchEvent(
				'/lines',
				{ expected_revision: 3, lines: Array.from({ length: 101 }, () => line) },
				rpc
			)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('turns the database’s own hundred-line cap into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '54000', message: 'A job can hold up to 100 lines.' }
		});

		const response = await LINES(
			patchEvent('/lines', { expected_revision: 3, lines: [line] }, rpc)
		);

		expect(response.status).toBe(422);
		await expect(response.json()).resolves.toMatchObject({
			field_errors: { form: 'A job can hold up to 100 lines.' }
		});
	});

	it('tells the browser to reload when someone else saved first', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'P0409' } });

		const response = await LINES(
			patchEvent('/lines', { expected_revision: 3, lines: [line] }, rpc)
		);

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
	});

	it('answers a member who may not edit the same way as a job that does not exist', async () => {
		mockedRequire.mockResolvedValue(context({ 'jobs.view': true }));
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		const response = await LINES(
			patchEvent('/lines', { expected_revision: 3, lines: [line] }, rpc)
		);

		expect(response.status).toBe(404);
	});
});

describe('job billing API', () => {
	it('sends the two decisions and nothing about collecting money', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4 }, error: null });

		const response = await BILLING(
			patchEvent(
				'/billing',
				{ expected_revision: 3, price_basis: 'job_total', billing_timing: 'manual' },
				rpc
			)
		);

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('set_job_billing', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 3,
			new_price_basis: 'job_total',
			new_billing_timing: 'manual'
		});
	});

	it('rejects an invoicing timing nobody defined', async () => {
		const rpc = vi.fn();

		const response = await BILLING(
			patchEvent(
				'/billing',
				{ expected_revision: 3, price_basis: 'job_total', billing_timing: 'whenever' },
				rpc
			)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes a basis the job’s type forbids to the database, which owns that rule', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'A one-off job is priced as a whole job.' }
		});

		const response = await BILLING(
			patchEvent(
				'/billing',
				{ expected_revision: 3, price_basis: 'per_visit', billing_timing: 'manual' },
				rpc
			)
		);

		expect(response.status).toBe(422);
		await expect(response.json()).resolves.toMatchObject({
			field_errors: { form: 'A one-off job is priced as a whole job.' }
		});
	});
});

describe('job discount API', () => {
	it('saves a named percentage discount', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4 }, error: null });

		const response = await DISCOUNT(
			patchEvent(
				'/discount',
				{ expected_revision: 3, type: 'percentage', name: 'Spring offer', value: 1000 },
				rpc
			)
		);

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('set_job_discount', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 3,
			new_name: 'Spring offer',
			new_type: 'percentage',
			new_value: 1000
		});
	});

	it('removes the discount when no type is sent', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4 }, error: null });

		await DISCOUNT(patchEvent('/discount', { expected_revision: 3, type: null }, rpc));

		expect(rpc.mock.calls[0][1]).toMatchObject({ new_type: null, new_value: null });
	});

	it('makes the person name a discount they are actually applying', async () => {
		const rpc = vi.fn();

		const response = await DISCOUNT(
			patchEvent('/discount', { expected_revision: 3, type: 'fixed', value: 500 }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.name).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a percentage above a hundred percent', async () => {
		const rpc = vi.fn();

		const response = await DISCOUNT(
			patchEvent(
				'/discount',
				{ expected_revision: 3, type: 'percentage', name: 'Too much', value: 12000 },
				rpc
			)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});

describe('job tax API', () => {
	it('sends a one-off custom rate without saving it to the shared list', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { revision: 4 }, error: null });

		const response = await TAX(
			patchEvent(
				'/tax',
				{
					expected_revision: 3,
					source: 'custom',
					custom_name: 'City tax',
					custom_rate_basis_points: 825
				},
				rpc
			)
		);

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('set_job_tax', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 3,
			new_source: 'custom',
			new_rate_id: null,
			new_custom_name: 'City tax',
			new_custom_rate_basis_points: 825,
			save_as_reusable: false
		});
	});

	it('makes a saved rate name which rate it means', async () => {
		const rpc = vi.fn();

		const response = await TAX(
			patchEvent('/tax', { expected_revision: 3, source: 'saved_rate' }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.rate_id).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('makes a custom rate carry both a name and a rate', async () => {
		const rpc = vi.fn();

		const response = await TAX(
			patchEvent('/tax', { expected_revision: 3, source: 'custom', custom_name: 'City tax' }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.custom_rate_basis_points).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('leaves the settings permission for saving a rate to the database', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		const response = await TAX(
			patchEvent(
				'/tax',
				{
					expected_revision: 3,
					source: 'custom',
					custom_name: 'City tax',
					custom_rate_basis_points: 825,
					save_as_reusable: true
				},
				rpc
			)
		);

		expect(rpc.mock.calls[0][1].save_as_reusable).toBe(true);
		expect(response.status).toBe(404);
	});

	it('rejects a tax option nobody defined', async () => {
		const rpc = vi.fn();

		const response = await TAX(patchEvent('/tax', { expected_revision: 3, source: 'vibes' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});
