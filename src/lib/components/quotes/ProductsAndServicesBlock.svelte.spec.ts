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
