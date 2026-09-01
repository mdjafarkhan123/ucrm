import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH as patchDiscount } from './discount/+server';
import { PATCH as patchTax } from './tax/+server';
import { PATCH as patchVisibility } from './visibility/+server';
import { PATCH as patchCopy } from './copy/+server';
import { PATCH as patchVersionAttachments } from './attachments/+server';
import { PATCH as patchLines } from './lines/+server';
import { POST as preview } from './preview/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

// The cost guard has its own reads; the line command under test only cares that it hands the lines on.
vi.mock('$lib/server/quotes/catalog-cost', () => ({
	withCatalogCost: vi.fn((_supabase, _org, _user, lines) => Promise.resolve(lines))
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000091';

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function commandEvent(body: unknown, rpcResult: unknown = { data: { revision: 3 }, error: null }) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}`, {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
		// Every proposal route shares this fake event, and each one's generated type names its own route
		// id, so the shape is handed over untyped rather than pretending to be one of them.
	} as unknown as Parameters<typeof patchDiscount>[0] &
		Parameters<typeof patchTax>[0] &
		Parameters<typeof patchVisibility>[0] &
		Parameters<typeof patchCopy>[0] &
		Parameters<typeof patchVersionAttachments>[0] &
		Parameters<typeof patchLines>[0] &
		Parameters<typeof preview>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const stale = {
	data: null,
	error: {
		code: 'P0409',
		message: 'Someone else changed this quote while you were editing. Reload and try again.'
	}
};

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context({ 'quotes.edit': true, 'quotes.view': true }));
});

describe('discount', () => {
	it('sends the name, kind, and value through the one command', async () => {
		const target = commandEvent({
			expected_revision: 4,
			name: '  Spring deal  ',
			type: 'percentage',
			value: 1000
		});

		await patchDiscount(target);

		expect(target.__rpc).toHaveBeenCalledWith('set_quote_draft_discount', {
			target_quote_id: quoteId,
			expected_revision: 4,
			new_name: 'Spring deal',
			new_type: 'percentage',
			new_value: 1000
		});
	});

	it('removes the discount by sending no kind at all', async () => {
		const target = commandEvent({ expected_revision: 4, type: null });

		await patchDiscount(target);

		expect(target.__rpc.mock.calls[0][1]).toMatchObject({
			new_type: null,
			new_name: null,
			new_value: null
		});
	});

	it('will not save without the revision it was shown', async () => {
		const target = commandEvent({ type: 'fixed', value: 500, name: 'Deal' });

		expect((await patchDiscount(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = commandEvent({ expected_revision: 1, type: null });

		expect((await patchDiscount(target)).status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('answers a stale save with a conflict the browser can reload on', async () => {
		const response = await patchDiscount(commandEvent({ expected_revision: 1, type: null }, stale));

		expect(response.status).toBe(409);
		expect((await response.json()).reason).toBe('stale');
	});
});

describe('tax', () => {
	it('freezes one saved rate', async () => {
		const target = commandEvent({
			expected_revision: 2,
			source: 'saved_rate',
			rate_id: '00000000-0000-4000-8000-000000000050'
		});

		await patchTax(target);

		expect(target.__rpc).toHaveBeenCalledWith('set_quote_draft_tax', {
			target_quote_id: quoteId,
			expected_revision: 2,
			new_source: 'saved_rate',
			new_rate_id: '00000000-0000-4000-8000-000000000050',
			new_custom_name: null,
			new_custom_rate_basis_points: null,
			save_as_reusable: false
		});
	});

	it('freezes a one-off custom rate', async () => {
		const target = commandEvent({
			expected_revision: 2,
			source: 'custom',
			custom_name: 'Sales tax',
			custom_rate_basis_points: 875
		});

		await patchTax(target);

		expect(target.__rpc).toHaveBeenCalledWith('set_quote_draft_tax', {
			target_quote_id: quoteId,
			expected_revision: 2,
			new_source: 'custom',
			new_rate_id: null,
			new_custom_name: 'Sales tax',
			new_custom_rate_basis_points: 875,
			save_as_reusable: false
		});
	});

	it('refuses a custom rate above one hundred percent before the database sees it', async () => {
		const target = commandEvent({
			expected_revision: 2,
			source: 'custom',
			custom_name: 'Sales tax',
			custom_rate_basis_points: 10001
		});

		expect((await patchTax(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});
});

describe('client visibility', () => {
	it('sends all four switches together', async () => {
		const target = commandEvent({
			expected_revision: 6,
			show_quantities: true,
			show_unit_prices: false,
			show_line_totals: true,
			show_totals: true
		});

		await patchVisibility(target);

		expect(target.__rpc.mock.calls[0][1]).toMatchObject({
			new_show_unit_prices: false,
			new_show_totals: true
		});
	});

	it('refuses a partial set, so a missing switch cannot silently turn something on', async () => {
		const target = commandEvent({ expected_revision: 6, show_totals: true });

		expect((await patchVisibility(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});
});

describe('proposal copy', () => {
	it('trims what was typed and clears what was emptied', async () => {
		const target = commandEvent({
			expected_revision: 3,
			introduction: '  Thanks for having us out.  ',
			client_message: ''
		});

		await patchCopy(target);

		expect(target.__rpc.mock.calls[0][1]).toMatchObject({
			new_introduction: 'Thanks for having us out.',
			new_client_message: null
		});
	});

	it('refuses an introduction longer than the page can hold', async () => {
		const target = commandEvent({ expected_revision: 3, introduction: 'a'.repeat(10001) });

		expect((await patchCopy(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});
});

describe('customer-visible files', () => {
	it('sends the references and who may see them', async () => {
		const target = commandEvent({
			expected_revision: 7,
			attachments: [
				{
					attachment_id: '00000000-0000-4000-8000-0000000000b1',
					display_name: 'Site plan',
					customer_visible: true
				}
			]
		});

		await patchVersionAttachments(target);
		const args = target.__rpc.mock.calls[0][1] as {
			new_attachments: Array<Record<string, unknown>>;
		};

		expect(target.__rpc.mock.calls[0][0]).toBe('replace_quote_version_attachments');
		expect(args.new_attachments[0]).toMatchObject({ customer_visible: true });
	});

	it('refuses a file that is not a file', async () => {
		const target = commandEvent({
			expected_revision: 7,
			attachments: [{ attachment_id: 'not-a-file', display_name: 'Site plan' }]
		});

		expect((await patchVersionAttachments(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});
});

describe('lines with choices', () => {
	const priced = {
		name: 'Consumer unit',
		category: 'product',
		quantity: 1,
		unit_price_minor: 45000,
		unit_cost_minor: 20000
	};

	it('carries the choice a line belongs to', async () => {
		const target = commandEvent({
			expected_revision: 4,
			lines: [
				priced,
				{ ...priced, name: 'Surge protection', selection_kind: 'optional', is_recommended: true }
			]
		});

		await patchLines(target);
		const args = target.__rpc.mock.calls[0][1] as { new_lines: Array<Record<string, unknown>> };

		expect(args.new_lines[0]).toMatchObject({ selection_kind: 'required', is_recommended: false });
		expect(args.new_lines[1]).toMatchObject({ selection_kind: 'optional', is_recommended: true });
	});

	it('lets a heading through with nothing but its words', async () => {
		const target = commandEvent({
			expected_revision: 4,
			lines: [{ line_kind: 'heading', name: 'Upstairs', unit_price_minor: 9999 }]
		});

		await patchLines(target);
		const args = target.__rpc.mock.calls[0][1] as { new_lines: Array<Record<string, unknown>> };

		expect(args.new_lines[0]).toMatchObject({ line_kind: 'heading', name: 'Upstairs' });
		expect(args.new_lines[0].unit_price_minor).toBeUndefined();
	});

	it('refuses to recommend work the customer is already getting', async () => {
		const target = commandEvent({
			expected_revision: 4,
			lines: [{ ...priced, is_recommended: true }]
		});

		expect((await patchLines(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});
});

describe('scenario preview', () => {
	it('asks for permission to see money, because the whole answer is money', async () => {
		const target = commandEvent(
			{ addon_ids: [] },
			{
				data: { subtotal_minor: 6000 },
				error: null
			}
		);

		await preview(target);

		expect(mockedRequire.mock.calls[0][1]).toBe('quotes.view_price');
		expect(target.__rpc).toHaveBeenCalledWith('preview_quote_version_totals', {
			target_quote_id: quoteId,
			selected_addon_ids: []
		});
	});

	it('prices the plain quote when nothing is chosen', async () => {
		const target = commandEvent({}, { data: { subtotal_minor: 9000 }, error: null });

		await preview(target);

		expect(target.__rpc.mock.calls[0][1]).toMatchObject({ selected_addon_ids: [] });
	});
});
