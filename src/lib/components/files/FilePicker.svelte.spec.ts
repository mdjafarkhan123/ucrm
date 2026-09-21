import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClient } from '@tanstack/query-core';
import { QueryClientProvider } from '@tanstack/svelte-query';
import FilePicker from './FilePicker.svelte';

// The picker is the reusable half of "attach an existing file": until a record editor mounts it in Part 5,
// this is what proves its promises -- the contract's section order, that only ticked files are sent, that a
// file already on the record cannot be ticked twice, and that a partial refusal keeps what failed on screen.

const originalFetch = globalThis.fetch;

function fileRow(id: string, name: string) {
	return {
		id,
		display_name: name,
		mime_type: 'image/jpeg',
		kind: 'image',
		size_bytes: 2048,
		has_thumbnail: false,
		folder_id: null,
		folder_name: null,
		origin_type: 'file_manager',
		origin_id: null,
		processing_state: 'available',
		uploaded_by: null,
		uploaded_by_name: null,
		created_at: '2026-09-20T10:00:00Z',
		trashed_at: null,
		usage_count: 0
	};
}

function listPage(files: ReturnType<typeof fileRow>[]) {
	return { files, next_cursor: null, can_manage: true, can_trash: true };
}

/**
 * Answers the picker's two reads from one place: the section it is showing, and the separate
 * "already on this record" read that decides which tiles are locked. Attach posts land in `attachCalls`.
 */
function mockApi(options: {
	onRecord?: ReturnType<typeof fileRow>[];
	library?: ReturnType<typeof fileRow>[];
	attachResponse?: unknown;
}) {
	const attachCalls: { url: string; body: Record<string, unknown> }[] = [];
	globalThis.fetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
		const url = typeof input === 'string' ? input : input.toString();
		if (url.startsWith('/api/files/links')) {
			attachCalls.push({ url, body: JSON.parse(String(init?.body ?? '{}')) });
			return Promise.resolve(
				new Response(
					JSON.stringify(
						options.attachResponse ?? { attached_count: 1, attached: ['file-1'], refused: [] }
					),
					{ status: 201, headers: { 'content-type': 'application/json' } }
				)
			);
		}
		const body = url.includes('view=on_record')
			? listPage(options.onRecord ?? [])
			: listPage(options.library ?? []);
		return Promise.resolve(
			new Response(JSON.stringify(body), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
	}) as typeof globalThis.fetch;
	return attachCalls;
}

function renderPicker(onClose = vi.fn()) {
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	const screen = render(
		FilePicker,
		{
			props: {
				open: true,
				entityType: 'job' as const,
				entityId: 'job-1',
				recordLabel: 'On this job',
				clientId: 'client-1',
				clientLabel: 'Ada Ashby',
				onClose
			}
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
	return { screen, onClose };
}

describe('FilePicker', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('leads with the record and its customer, then the rest of the library', async () => {
		mockApi({});
		renderPicker();

		// The order the behavior contract fixes: this record, this customer, then Recent, Photos, Documents
		// and All files.
		await expect.element(page.getByRole('button', { name: 'On this job' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Ada Ashby' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Recent' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'All files' })).toBeVisible();
	});

	it('asks only for files that can actually be attached', async () => {
		mockApi({});
		renderPicker();

		await vi.waitFor(() => expect(globalThis.fetch).toHaveBeenCalled());
		const urls = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls.map((call) =>
			String(call[0])
		);
		expect(urls.some((url) => url.includes('attachable=1'))).toBe(true);
		expect(urls.some((url) => url.includes('entity_type=job&entity_id=job-1'))).toBe(true);
	});

	it('sends only the ticked files, then closes', async () => {
		const attachCalls = mockApi({
			library: [fileRow('file-1', 'boiler-before.jpg'), fileRow('file-2', 'invoice.jpg')]
		});
		const { onClose } = renderPicker();

		await page.getByRole('button', { name: 'All files' }).click();
		await page.getByRole('button', { name: /boiler-before\.jpg/ }).click();
		await page.getByRole('button', { name: 'Add file' }).click();

		await vi.waitFor(() => expect(attachCalls).toHaveLength(1));
		expect(attachCalls[0].body).toEqual({
			file_ids: ['file-1'],
			entity_type: 'job',
			entity_id: 'job-1'
		});
		await vi.waitFor(() => expect(onClose).toHaveBeenCalled());
	});

	it('locks a file that is already on this record', async () => {
		const attachCalls = mockApi({
			onRecord: [fileRow('file-1', 'boiler-before.jpg')],
			library: [fileRow('file-1', 'boiler-before.jpg')]
		});
		renderPicker();

		await page.getByRole('button', { name: 'All files' }).click();
		await expect.element(page.getByText('Already added')).toBeVisible();

		// The tile itself cannot be ticked, so there is no second use to make and nothing to send.
		await expect.element(page.getByRole('button', { name: /boiler-before\.jpg/ })).toBeDisabled();
		await expect.element(page.getByRole('button', { name: 'Add file' })).toBeDisabled();
		expect(attachCalls).toHaveLength(0);
	});

	it('keeps the picker open and says which file was refused', async () => {
		mockApi({
			library: [fileRow('file-1', 'boiler-before.jpg'), fileRow('file-2', 'still-checking.jpg')],
			attachResponse: {
				attached_count: 1,
				attached: ['file-1'],
				refused: [
					{
						file_id: 'file-2',
						reason: 'That file is still being checked, so it cannot be attached yet.'
					}
				]
			}
		});
		const { onClose } = renderPicker();

		await page.getByRole('button', { name: 'All files' }).click();
		await page.getByRole('button', { name: /boiler-before\.jpg/ }).click();
		await page.getByRole('button', { name: /still-checking\.jpg/ }).click();
		await page.getByRole('button', { name: 'Add 2 files' }).click();

		await expect
			.element(page.getByText('That file is still being checked, so it cannot be attached yet.'))
			.toBeVisible();
		expect(onClose).not.toHaveBeenCalled();
	});
});
