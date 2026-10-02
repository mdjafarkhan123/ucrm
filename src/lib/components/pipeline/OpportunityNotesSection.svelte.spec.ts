import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import OpportunityNotesSection from './OpportunityNotesSection.svelte';

// The component reports its outcome through the shared toast manager, which the app shell provides; here
// there is no shell, so a stub stands in and nothing asserts on it.
vi.mock('$lib/components/ui/ToastManager.svelte', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/components/ui/ToastManager.svelte')>()),
	getToastManager: () => ({ success: vi.fn(), error: vi.fn() })
}));

// The Brief's Notes block: immediate-save, the card's Request or Quote and its Client as targets, gated by
// pipeline.edit.

function noteFixture(overrides: Record<string, unknown> = {}) {
	return {
		id: 'note-1',
		body: 'Called the client back',
		pinned: false,
		created_by: 'user-1',
		edited_by: null,
		edited_at: null,
		created_at: '2026-08-10T00:00:00.000Z',
		updated_at: '2026-08-10T00:00:00.000Z',
		entity_type: 'request',
		entity_id: 'request-1',
		files: [],
		mention_user_ids: [],
		...overrides
	};
}

function renderSection(
	props: { canEdit?: boolean; hasClient?: boolean; quoteCard?: boolean } = {}
) {
	const queryClient = createQueryClient();
	return render(
		OpportunityNotesSection,
		{
			props: {
				opportunityId: 'opp-1',
				requestId: props.quoteCard ? null : 'request-1',
				quoteId: props.quoteCard ? 'quote-1' : null,
				clientId: (props.hasClient ?? true) ? 'client-1' : null,
				canEdit: props.canEdit ?? true
			}
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
}

const originalFetch = globalThis.fetch;

function mockFetch(notesBody: { notes: unknown[] }) {
	globalThis.fetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
		const url = String(input);
		if (url.endsWith('/api/pipeline/teammates')) {
			return Promise.resolve(
				new Response(
					JSON.stringify({
						members: [{ id: 'user-2', full_name: 'Sam Lee', avatar_url: null }]
					}),
					{ status: 200 }
				)
			);
		}
		if (url.endsWith('/notes') && (!init || init.method === undefined)) {
			return Promise.resolve(new Response(JSON.stringify(notesBody), { status: 200 }));
		}
		if (url.includes('/notes') && init?.method === 'POST') {
			return Promise.resolve(
				new Response(JSON.stringify({ note: noteFixture({ id: 'note-2' }) }), { status: 201 })
			);
		}
		if (url.includes('/notes/') && init?.method === 'PATCH') {
			return Promise.resolve(
				new Response(JSON.stringify({ note: noteFixture({ body: 'Updated body' }) }), {
					status: 200
				})
			);
		}
		if (url.includes('/notes/') && init?.method === 'DELETE') {
			return Promise.resolve(
				new Response(JSON.stringify({ unlinked: true, note_deleted: true }), { status: 200 })
			);
		}
		return Promise.resolve(new Response(JSON.stringify({ profiles: [] }), { status: 200 }));
	});
}

describe('OpportunityNotesSection', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('shows the empty state and an Add note action', async () => {
		mockFetch({ notes: [] });
		renderSection();

		await expect.element(page.getByText('No notes yet')).toBeVisible();
	});

	it('lists Notes from both the Request and the Client, badged by target', async () => {
		mockFetch({
			notes: [
				noteFixture(),
				noteFixture({ id: 'note-2', entity_type: 'client', body: 'Client note' })
			]
		});
		renderSection();

		await expect.element(page.getByText('Called the client back')).toBeVisible();
		await expect.element(page.getByText('Client note')).toBeVisible();
		const list = page.getByRole('list');
		await expect.element(list.getByText('Request', { exact: true })).toBeVisible();
		await expect.element(list.getByText('Client', { exact: true })).toBeVisible();
	});

	it('creates a note against the chosen target', async () => {
		mockFetch({ notes: [] });
		renderSection();

		await page.getByRole('button', { name: 'Add a note' }).click();
		await page.getByLabelText('Add a note').fill('New note body');
		await page.getByRole('button', { name: 'Add note' }).click();

		await expect
			.poll(() =>
				vi.mocked(globalThis.fetch).mock.calls.some(([, init]) => init?.method === 'POST')
			)
			.toBe(true);
		const call = vi.mocked(globalThis.fetch).mock.calls.find(([, init]) => init?.method === 'POST');
		expect(JSON.parse(call?.[1]?.body as string)).toEqual({
			entity_type: 'request',
			body: 'New note body',
			file_ids: [],
			mention_user_ids: []
		});
	});

	it('writes a new note onto the Quote on a Quote card', async () => {
		mockFetch({ notes: [] });
		renderSection({ quoteCard: true });

		await page.getByRole('button', { name: 'Add a note' }).click();
		await expect.element(page.getByText('Quote', { exact: true })).toBeVisible();
		expect(page.getByText('Request', { exact: true }).elements()).toHaveLength(0);
		await page.getByLabelText('Add a note').fill('Quote note');
		await page.getByRole('button', { name: 'Add note' }).click();

		await expect
			.poll(() =>
				vi.mocked(globalThis.fetch).mock.calls.some(([, init]) => init?.method === 'POST')
			)
			.toBe(true);
		const call = vi.mocked(globalThis.fetch).mock.calls.find(([, init]) => init?.method === 'POST');
		expect(JSON.parse(call?.[1]?.body as string).entity_type).toBe('quote');
	});

	it('sends a picked @mention with the note', async () => {
		mockFetch({ notes: [] });
		renderSection();

		await page.getByRole('button', { name: 'Add a note' }).click();
		const box = page.getByLabelText('Add a note');
		await box.fill('Please call @Sa');
		await page.getByRole('option', { name: 'Sam Lee' }).click();
		await expect.element(box).toHaveValue('Please call @Sam Lee ');
		await page.getByRole('button', { name: 'Add note' }).click();

		await expect
			.poll(() =>
				vi.mocked(globalThis.fetch).mock.calls.some(([, init]) => init?.method === 'POST')
			)
			.toBe(true);
		const call = vi.mocked(globalThis.fetch).mock.calls.find(([, init]) => init?.method === 'POST');
		expect(JSON.parse(call?.[1]?.body as string).mention_user_ids).toEqual(['user-2']);
	});

	it("shows a note's photo through the card", async () => {
		mockFetch({
			notes: [
				noteFixture({
					files: [
						{
							id: 'file-1',
							display_name: 'roof.jpg',
							mime_type: 'image/jpeg',
							kind: 'image',
							size_bytes: 1000,
							has_thumbnail: true,
							processing_state: 'available'
						}
					]
				})
			]
		});
		renderSection();

		await expect.element(page.getByRole('button', { name: 'Open roof.jpg' })).toBeVisible();
	});

	it('deletes a note through the confirm dialog', async () => {
		mockFetch({ notes: [noteFixture()] });
		renderSection();

		await page.getByRole('button', { name: 'Note actions' }).click();
		await page.getByText('Delete').click();
		await page.getByRole('button', { name: 'Delete note' }).click();

		await expect
			.poll(() =>
				vi.mocked(globalThis.fetch).mock.calls.some(([, init]) => init?.method === 'DELETE')
			)
			.toBe(true);
	});

	it('hides every write action for a read-only member', async () => {
		mockFetch({ notes: [noteFixture()] });
		renderSection({ canEdit: false });

		await expect.element(page.getByText('Called the client back')).toBeVisible();
		expect(page.getByRole('button', { name: 'Add note' }).elements()).toHaveLength(0);
		expect(page.getByRole('button', { name: 'Note actions' }).elements()).toHaveLength(0);
	});

	it('hides the Client target when the card has no Client', async () => {
		mockFetch({ notes: [] });
		renderSection({ hasClient: false });

		await page.getByRole('button', { name: 'Add a note' }).click();
		expect(page.getByText('Client', { exact: true }).elements()).toHaveLength(0);
	});
});
