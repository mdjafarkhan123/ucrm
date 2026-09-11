import { page, userEvent } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClient } from '@tanstack/query-core';
import { QueryClientProvider } from '@tanstack/svelte-query';
import GlobalSearchDialog from './GlobalSearchDialog.svelte';

const originalFetch = globalThis.fetch;

function renderDialog(onClose = vi.fn()) {
	const queryClient = new QueryClient({
		defaultOptions: { queries: { retry: false, staleTime: 30_000 } }
	});
	const screen = render(
		GlobalSearchDialog,
		{ props: { open: true, userId: 'user-1', onClose } },
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
	return { screen, onClose };
}

function mockSearch(body: unknown, status = 200) {
	globalThis.fetch = vi.fn(() =>
		Promise.resolve(
			new Response(JSON.stringify(body), {
				status,
				headers: { 'content-type': 'application/json' }
			})
		)
	);
}

describe('GlobalSearchDialog', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('waits for two characters before searching', async () => {
		mockSearch({ query: 'r', groups: {} });
		renderDialog();

		await page.getByRole('searchbox', { name: 'Search clients, work, or conversations' }).fill('r');
		await new Promise((resolve) => setTimeout(resolve, 350));

		expect(globalThis.fetch).not.toHaveBeenCalled();
		await expect
			.element(page.getByText('Enter at least 2 characters to search your records.'))
			.toBeVisible();
	});

	it('debounces the request and renders the API groups as record links', async () => {
		mockSearch({
			query: 'roof',
			groups: {
				clients: [
					{
						id: 'client-1',
						type: 'client',
						title: 'Rooftop Bakery',
						subtitle: 'Commercial client',
						href: '/clients/client-1'
					}
				],
				jobs: [
					{
						id: 'job-1',
						type: 'job',
						title: 'Job #14 · Roof repair',
						subtitle: 'Rooftop Bakery',
						href: '/jobs/job-1'
					}
				]
			}
		});
		renderDialog();

		await page
			.getByRole('searchbox', { name: 'Search clients, work, or conversations' })
			.fill('roof');

		await vi.waitFor(() => expect(globalThis.fetch).toHaveBeenCalledWith('/api/search?q=roof'));
		await expect.element(page.getByRole('heading', { name: 'Clients' })).toBeVisible();
		await expect.element(page.getByRole('heading', { name: 'Jobs' })).toBeVisible();
		await expect
			.element(page.getByRole('link', { name: /^Rooftop Bakery Commercial/ }))
			.toHaveAttribute('href', '/clients/client-1');
		await expect.element(page.getByText('2 results')).toBeVisible();
	});

	it('moves from the search field through results with arrow keys', async () => {
		mockSearch({
			query: 'roof',
			groups: {
				clients: [
					{
						id: 'client-1',
						type: 'client',
						title: 'Rooftop Bakery',
						subtitle: null,
						href: '/clients/client-1'
					}
				],
				jobs: [
					{
						id: 'job-1',
						type: 'job',
						title: 'Job #14 · Roof repair',
						subtitle: null,
						href: '/jobs/job-1'
					}
				]
			}
		});
		renderDialog();
		const input = page.getByRole('searchbox', { name: 'Search clients, work, or conversations' });
		await input.fill('roof');
		await expect.element(page.getByRole('link', { name: 'Rooftop Bakery' })).toBeVisible();

		await input.click();
		await userEvent.keyboard('{ArrowDown}');
		await expect.element(page.getByRole('link', { name: 'Rooftop Bakery' })).toHaveFocus();
		await userEvent.keyboard('{ArrowDown}');
		await expect.element(page.getByRole('link', { name: /Job #14/ })).toHaveFocus();
		await userEvent.keyboard('{ArrowUp}');
		await expect.element(page.getByRole('link', { name: 'Rooftop Bakery' })).toHaveFocus();
	});

	it('shows an actionable error state', async () => {
		mockSearch({ error: 'Unavailable' }, 500);
		renderDialog();

		await page
			.getByRole('searchbox', { name: 'Search clients, work, or conversations' })
			.fill('roof');

		await expect
			.element(page.getByRole('heading', { name: 'Search is unavailable' }))
			.toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Try Again' })).toBeVisible();
	});

	it('shows a useful empty state when no permitted record matches', async () => {
		mockSearch({ query: 'roof', groups: {} });
		renderDialog();

		await page
			.getByRole('searchbox', { name: 'Search clients, work, or conversations' })
			.fill('roof');

		await expect.element(page.getByRole('heading', { name: 'No matches found' })).toBeVisible();
		await expect.element(page.getByText(/No records match “roof”/)).toBeVisible();
	});

	it('reopens with the cached result instead of issuing the same request again', async () => {
		mockSearch({
			query: 'roof',
			groups: {
				clients: [
					{
						id: 'client-1',
						type: 'client',
						title: 'Rooftop Bakery',
						subtitle: null,
						href: '/clients/client-1'
					}
				]
			}
		});
		const { screen, onClose } = renderDialog();
		await page
			.getByRole('searchbox', { name: 'Search clients, work, or conversations' })
			.fill('roof');
		await expect.element(page.getByRole('link', { name: 'Rooftop Bakery' })).toBeVisible();

		await screen.rerender({ open: false, userId: 'user-1', onClose });
		await screen.rerender({ open: true, userId: 'user-1', onClose });

		await expect.element(page.getByRole('link', { name: 'Rooftop Bakery' })).toBeVisible();
		expect(globalThis.fetch).toHaveBeenCalledTimes(1);
	});
});
