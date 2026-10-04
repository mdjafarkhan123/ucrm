import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import Harness from './SetupFilesField.harness.svelte';

// Client onboarding B9b: a protected document in setup (Jafar's decisions, 2026-10-04). An administrator doing
// setup sees that it was received and cannot open it; the business owner can open it and read who has.

const DOCUMENT_ID = '22222222-2222-4222-8222-222222222222';
const originalFetch = globalThis.fetch;

function serve(canOpen: boolean) {
	const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
		const url = String(input);
		if (url.startsWith('/api/setup/protected-documents?'))
			return Response.json({
				can_open: canOpen,
				documents: [
					{
						id: DOCUMENT_ID,
						name: 'march-bill.pdf',
						size_bytes: 120_000,
						state: 'ready',
						problem: null,
						uploaded_at: '2026-10-04T10:00:00Z',
						delete_after: null
					}
				]
			});
		if (url === `/api/setup/protected-documents/${DOCUMENT_ID}` && init?.method === 'DELETE')
			return Response.json({ removed: true });
		if (url === `/api/setup/protected-documents/${DOCUMENT_ID}/history`)
			return Response.json({
				history: [
					{ action: 'uploaded', who: 'Sam Admin', at: '2026-10-04T10:00:00Z' },
					{ action: 'opened', who: 'Uplift', at: '2026-10-05T09:00:00Z' }
				]
			});
		return new Response(null, { status: 404 });
	});
	globalThis.fetch = fetch as typeof globalThis.fetch;
	return fetch;
}

function renderField() {
	return render(
		Harness,
		{ props: { value: JSON.stringify([DOCUMENT_ID]) } },
		{ wrapper: QueryClientProvider, wrapperProps: { client: createQueryClient() } }
	);
}

afterEach(() => {
	globalThis.fetch = originalFetch;
});

describe('a protected document in setup', () => {
	it('tells an administrator it was received, with no way to open it or read its history', async () => {
		serve(false);
		renderField();
		await expect.element(page.getByText('Received · 117 KB')).toBeVisible();
		await expect.element(page.getByText('march-bill.pdf')).toBeVisible();
		expect(page.getByRole('link', { name: 'march-bill.pdf' }).query()).toBeNull();
		expect(page.getByRole('button', { name: 'History' }).query()).toBeNull();
		await expect.element(page.getByText(/Kept private/)).toBeVisible();
	});

	it('lets the owner open it, without a preview link being fetched on hover, and read who opened it', async () => {
		serve(true);
		renderField();
		const link = page.getByRole('link', { name: 'march-bill.pdf' });
		await expect
			.element(link)
			.toHaveAttribute('href', `/api/setup/protected-documents/${DOCUMENT_ID}`);
		await expect.element(link).toHaveAttribute('data-sveltekit-preload-data', 'off');
		await page.getByRole('button', { name: 'History' }).click();
		await expect.element(page.getByText('Opened by Uplift')).toBeVisible();
		await expect.element(page.getByText('Uploaded by Sam Admin')).toBeVisible();
	});

	it('deletes the document for good when it is removed, then clears the answer', async () => {
		const fetch = serve(false);
		renderField();
		await page.getByRole('button', { name: 'Delete march-bill.pdf' }).click();
		await vi.waitFor(() =>
			expect(fetch).toHaveBeenCalledWith(`/api/setup/protected-documents/${DOCUMENT_ID}`, {
				method: 'DELETE'
			})
		);
		await expect.element(page.getByTestId('value')).toHaveTextContent('');
	});

	it('keeps the document in the answer when it could not be deleted', async () => {
		const fetch = serve(false);
		fetch.mockImplementationOnce(fetch.getMockImplementation()!);
		renderField();
		await expect.element(page.getByText('march-bill.pdf')).toBeVisible();
		fetch.mockImplementationOnce(async () =>
			Response.json({ error: 'Try again in a moment.' }, { status: 503 })
		);
		await page.getByRole('button', { name: 'Delete march-bill.pdf' }).click();
		await expect.element(page.getByRole('alert')).toHaveTextContent('Try again in a moment.');
		await expect.element(page.getByTestId('value')).toHaveTextContent(DOCUMENT_ID);
	});
});
