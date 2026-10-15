import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import ProductsAndServicesBlock from './ProductsAndServicesBlock.svelte';

function renderBlock(quoteChoices: boolean) {
	const queryClient = createQueryClient();
	return render(
		ProductsAndServicesBlock,
		{
			props: {
				alwaysEditing: true,
				editable: true,
				quoteChoices,
				lines: [],
				onDraftChange: vi.fn()
			}
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
}

describe('ProductsAndServicesBlock quote choices', () => {
	it('keeps Quote-only controls out of the shared Request editor', async () => {
		const screen = renderBlock(false);

		expect(await page.getByText('Tax exempt').elements()).toHaveLength(0);
		expect(await page.getByRole('button', { name: 'Add heading' }).elements()).toHaveLength(0);
		screen.unmount();
	});

	it('offers text and heading controls for Quotes', async () => {
		const screen = renderBlock(true);
		await page.getByRole('button', { name: 'Add line item' }).click();

		await expect.element(page.getByRole('button', { name: 'Add text' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Add heading' })).toBeVisible();
		screen.unmount();
	});

	// Tax and the customer's choice are moves in the line's own menu rather than controls sitting on the
	// card, so this is where they have to be findable.
	it('keeps tax and customer choice in the line menu', async () => {
		const screen = renderBlock(true);
		await page.getByRole('button', { name: 'Add line item' }).click();
		await page.getByRole('button', { name: 'Line actions' }).click();

		await expect.element(page.getByRole('menuitem', { name: 'Mark tax exempt' })).toBeVisible();
		await expect
			.element(page.getByRole('menuitem', { name: 'Make it an optional add-on' }))
			.toBeVisible();
		screen.unmount();
	});

	it('adds non-priced document rows without showing money fields on them', async () => {
		const screen = renderBlock(true);
		await page.getByRole('button', { name: 'Add line item' }).click();

		await page.getByRole('button', { name: 'Add heading' }).click();
		await expect.element(page.getByRole('textbox', { name: 'Heading' })).toBeVisible();
		expect(await page.getByRole('textbox', { name: 'Unit price' }).elements()).toHaveLength(1);
		screen.unmount();
	});
});

describe('ProductsAndServicesBlock saved totals', () => {
	const line = {
		id: 'line-1',
		catalog_item_id: null,
		category: 'service',
		is_labor: false,
		name: 'Cedar fence panels',
		description: '6 ft tall panels',
		unit_label: 'ft',
		quantity: 64,
		unit_price_minor: 4200,
		unit_cost_minor: 0,
		is_taxable: true,
		line_total_minor: 268800,
		line_cost_total_minor: 0,
		image_file_id: null,
		line_kind: 'priced',
		selection_kind: 'required'
	} as const;

	function renderSaved(totals: Record<string, unknown> | null) {
		const queryClient = createQueryClient();
		return render(
			ProductsAndServicesBlock,
			{
				props: { lines: [line], subtotalMinor: 268800, totals } as never
			},
			{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
		);
	}

	it('closes the card with discount, tax and the record total the database worked out', async () => {
		const screen = renderSaved({
			discountMinor: 35000,
			discountLabel: 'Fall booking discount',
			taxMinor: 13440,
			taxLabel: 'GST 5%',
			totalMinor: 247240,
			totalLabel: 'Invoice total'
		});

		await expect.element(page.getByText('Subtotal')).toBeInTheDocument();
		await expect.element(page.getByText('$2,688.00', { exact: true }).first()).toBeInTheDocument();
		await expect.element(page.getByText('Fall booking discount')).toBeInTheDocument();
		await expect.element(page.getByText('−$350.00')).toBeInTheDocument();
		await expect.element(page.getByText('GST 5%')).toBeInTheDocument();
		await expect.element(page.getByText('$134.40')).toBeInTheDocument();
		await expect.element(page.getByText('Invoice total')).toBeInTheDocument();
		await expect.element(page.getByText('$2,472.40')).toBeInTheDocument();
		await expect.element(page.getByText('1 item')).toBeInTheDocument();
		screen.unmount();
	});

	it('shows only the subtotal when the page gives no totals', async () => {
		const screen = renderSaved(null);

		await expect.element(page.getByText('Subtotal')).toBeInTheDocument();
		expect(await page.getByText('Invoice total').elements()).toHaveLength(0);
		screen.unmount();
	});
});
