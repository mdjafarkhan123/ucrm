import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import PriceBookDrawer from './PriceBookDrawer.svelte';
import type { CatalogItem } from '$lib/quotes/api';

// The shared price book: browse, add several without reopening, and never see a cost you may not see.
// See `Memory/campaigns/quotes/parts/02b-price-book-drawer.md`.

function itemFixture(overrides: Partial<CatalogItem> = {}): CatalogItem {
	return {
		id: 'item-1',
		category: 'service',
		name: 'Gutter clearing',
		description: 'Clear and flush every run',
		unit_label: null,
		unit_price_minor: 12500,
		unit_cost_minor: 4000,
		is_taxable: true,
		is_labor: false,
		archived_at: null,
		updated_at: '2026-08-24T00:00:00Z',
		revision: 1,
		...overrides
	};
}

const originalFetch = globalThis.fetch;

function mockCatalog(items: CatalogItem[], canViewCost = true) {
	globalThis.fetch = vi.fn(() =>
		Promise.resolve(
			new Response(JSON.stringify({ items, next_cursor: null, can_view_cost: canViewCost }), {
				status: 200
			})
		)
	) as unknown as typeof fetch;
}

function renderDrawer(props: {
	addedCounts?: Record<string, number>;
	onAdd?: (item: CatalogItem) => void;
	onAddCustomLine?: () => void;
	onClose?: () => void;
}) {
	const queryClient = createQueryClient();
	return render(
		PriceBookDrawer,
		{
			props: {
				open: true,
				currencyCode: 'USD',
				locale: 'en-US',
				addedCounts: props.addedCounts ?? {},
				onAdd: props.onAdd ?? (() => {}),
				onAddCustomLine: props.onAddCustomLine ?? (() => {}),
				onClose: props.onClose ?? (() => {})
			}
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
}

describe('PriceBookDrawer', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('lists saved items with their price', async () => {
		mockCatalog([itemFixture()]);
		renderDrawer({});

		await expect.element(page.getByText('Gutter clearing')).toBeVisible();
		await expect.element(page.getByText('$125.00')).toBeVisible();
	});

	it('hands each pick to the caller and keeps the drawer open', async () => {
		const onAdd = vi.fn();
		const onClose = vi.fn();
		mockCatalog([itemFixture(), itemFixture({ id: 'item-2', name: 'Downspout repair' })]);
		renderDrawer({ onAdd, onClose });

		await page.getByRole('button', { name: 'Add', exact: true }).first().click();

		expect(onAdd).toHaveBeenCalledTimes(1);
		expect(onAdd.mock.calls[0][0].id).toBe('item-1');
		expect(onClose).not.toHaveBeenCalled();
		await expect.element(page.getByText('Downspout repair')).toBeVisible();
	});

	it('turns an added row into a count, so a second click on the same spot cannot add it again', async () => {
		mockCatalog([itemFixture()]);
		renderDrawer({ addedCounts: { 'item-1': 2 } });

		await expect.element(page.getByText('Added 2×')).toBeVisible();
		expect(await page.getByRole('button', { name: 'Add', exact: true }).elements()).toHaveLength(0);
	});

	it('still allows a deliberate second copy', async () => {
		const onAdd = vi.fn();
		mockCatalog([itemFixture()]);
		renderDrawer({ addedCounts: { 'item-1': 1 }, onAdd });

		await page.getByRole('button', { name: 'Add another Gutter clearing' }).click();

		expect(onAdd).toHaveBeenCalledTimes(1);
	});

	it('shows internal cost only to someone who may see it', async () => {
		mockCatalog([itemFixture()]);
		const withCost = renderDrawer({});
		await expect.element(page.getByText('Cost $40.00')).toBeVisible();
		withCost.unmount();

		mockCatalog([itemFixture({ unit_cost_minor: undefined })], false);
		renderDrawer({});
		await expect.element(page.getByText('Gutter clearing')).toBeVisible();
		expect(await page.getByText('Cost $40.00').elements()).toHaveLength(0);
	});

	it('asks the server for one category rather than filtering a downloaded catalog', async () => {
		mockCatalog([itemFixture()]);
		renderDrawer({});
		await expect.element(page.getByText('Gutter clearing')).toBeVisible();

		await page.getByText('Products', { exact: true }).click();

		await vi.waitFor(() => {
			const urls = (globalThis.fetch as unknown as { mock: { calls: unknown[][] } }).mock.calls.map(
				(call) => String(call[0])
			);
			expect(urls.some((url) => url.includes('category=product'))).toBe(true);
		});
	});

	it('closes through Done and starts a one-off line through Add custom line', async () => {
		const onClose = vi.fn();
		const onAddCustomLine = vi.fn();
		mockCatalog([itemFixture()]);
		renderDrawer({ onClose, onAddCustomLine });

		await page.getByRole('button', { name: 'Add custom line' }).click();
		expect(onAddCustomLine).toHaveBeenCalledTimes(1);

		await page.getByRole('button', { name: 'Done' }).click();
		expect(onClose).toHaveBeenCalledTimes(1);
	});
});
