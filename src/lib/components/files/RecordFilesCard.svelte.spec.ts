import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClient } from '@tanstack/query-core';
import { QueryClientProvider } from '@tanstack/svelte-query';
import RecordFilesCard from './RecordFilesCard.svelte';

// A record's file area, now read from the central catalog. What matters here is that it asks the right
// question, draws photos as photos, and that taking a file off the record removes one use rather than the
// File -- which is the whole difference between this card and the attachments card it replaces.

const originalFetch = globalThis.fetch;

function fileRow(id: string, name: string, overrides: Record<string, unknown> = {}) {
	return {
		id,
		display_name: name,
		mime_type: name.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg',
		kind: name.endsWith('.pdf') ? 'document' : 'image',
		size_bytes: 2048,
		has_thumbnail: true,
		folder_id: null,
		folder_name: null,
		origin_type: 'client',
		origin_id: 'client-1',
		processing_state: 'available',
		uploaded_by: null,
		uploaded_by_name: null,
		created_at: '2026-09-20T10:00:00Z',
		trashed_at: null,
		usage_count: 1,
		...overrides
	};
}

function mockApi(files: ReturnType<typeof fileRow>[]) {
	const detachCalls: { method: string; body: Record<string, unknown> }[] = [];
	const listUrls: string[] = [];
	globalThis.fetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
		const url = typeof input === 'string' ? input : input.toString();
		if (url.startsWith('/api/files/links')) {
			detachCalls.push({
				method: String(init?.method ?? 'GET'),
				body: JSON.parse(String(init?.body ?? '{}'))
			});
			return Promise.resolve(
				new Response(JSON.stringify({ removed: true }), {
					status: 200,
					headers: { 'content-type': 'application/json' }
				})
			);
		}
		listUrls.push(url);
		return Promise.resolve(
			new Response(
				JSON.stringify({ files, next_cursor: null, can_manage: true, can_trash: true }),
				{ status: 200, headers: { 'content-type': 'application/json' } }
			)
		);
	}) as typeof globalThis.fetch;
	return { detachCalls, listUrls };
}

function renderCard(canManage = true) {
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		RecordFilesCard,
		{
			props: {
				entityType: 'client' as const,
				entityId: 'client-1',
				recordLabel: 'this client',
				canManage
			}
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
}

describe('RecordFilesCard', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('asks the catalog for the files linked to this record', async () => {
		const { listUrls } = mockApi([]);
		renderCard();

		await vi.waitFor(() => expect(listUrls.length).toBeGreaterThan(0));
		expect(listUrls[0]).toContain('view=on_record');
		expect(listUrls[0]).toContain('entity_type=client');
		expect(listUrls[0]).toContain('entity_id=client-1');
	});

	it('shows photos and documents from the catalog', async () => {
		mockApi([fileRow('file-1', 'boiler-before.jpg'), fileRow('file-2', 'report.pdf')]);
		renderCard();

		await expect
			.element(page.getByRole('button', { name: /View boiler-before\.jpg/ }))
			.toBeVisible();
		await expect.element(page.getByText('report.pdf')).toBeVisible();
	});

	it('says how many other places a file is used', async () => {
		mockApi([fileRow('file-2', 'report.pdf', { usage_count: 3 })]);
		renderCard();

		await expect.element(page.getByText(/Used in 3 places/)).toBeVisible();
	});

	it('removes one use of the file, and says the file itself stays', async () => {
		const { detachCalls } = mockApi([fileRow('file-1', 'boiler-before.jpg')]);
		renderCard();

		await page.getByRole('button', { name: /Remove boiler-before\.jpg from this record/ }).click();
		await expect.element(page.getByText(/It stays in your files/)).toBeVisible();
		await page.getByRole('button', { name: 'Remove', exact: true }).click();

		await vi.waitFor(() => expect(detachCalls).toHaveLength(1));
		expect(detachCalls[0].method).toBe('DELETE');
		expect(detachCalls[0].body).toEqual({
			file_id: 'file-1',
			entity_type: 'client',
			entity_id: 'client-1'
		});
	});

	it('offers nothing to change when the reader cannot edit the record', async () => {
		mockApi([fileRow('file-1', 'boiler-before.jpg')]);
		renderCard(false);

		await expect
			.element(page.getByRole('button', { name: /View boiler-before\.jpg/ }))
			.toBeVisible();
		await expect
			.element(page.getByRole('button', { name: /Remove boiler-before\.jpg from this record/ }))
			.not.toBeInTheDocument();
		await expect.element(page.getByRole('button', { name: 'Add' })).not.toBeInTheDocument();
	});
});
