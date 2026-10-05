import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import SetupPreview from './SetupPreview.svelte';
import type { PreviewNote } from '$lib/setup/preview';

// Client onboarding E3: the page promises "Your notes are saved as you go". A note typed and then left — the
// tab closed, the phone locked — must already be kept, without the client first clicking out of the box.

const originalFetch = globalThis.fetch;

function serve() {
	const notes: PreviewNote[] = [];
	const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
		const url = String(input);
		if (url === '/api/setup/preview')
			return Response.json({
				versions: [
					{
						version: 1,
						released_at: '2026-10-05T07:09:00Z',
						correction_round: true,
						notes_sent_at: null,
						notes_sent_by_name: null,
						cards: [
							{ id: 'c1', title: 'Services', summary: 'Your services.', link: null, screenshots: [] }
						],
						notes
					}
				]
			});
		if (url === '/api/setup/preview/notes' && init?.method === 'POST') {
			const body = JSON.parse(String(init.body));
			notes.splice(0, notes.length, {
				card_id: body.card_id,
				choice: body.choice,
				note: body.note,
				screenshots: [],
				updated_at: '2026-10-05T07:10:00Z',
				kind: null
			});
			return Response.json({ status: 'saved' });
		}
		return new Response(null, { status: 404 });
	});
	globalThis.fetch = fetch as typeof globalThis.fetch;
	return fetch;
}

const noteSaves = (fetch: ReturnType<typeof serve>) =>
	fetch.mock.calls
		.filter(([url]) => String(url) === '/api/setup/preview/notes')
		.map(([, init]) => JSON.parse(String(init?.body)));

afterEach(() => {
	globalThis.fetch = originalFetch;
});

describe('a note on the preview', () => {
	it('saves while the client types, without leaving the box', async () => {
		const fetch = serve();
		render(
			SetupPreview,
			{ props: { userId: 'user-1' } },
			{ wrapper: QueryClientProvider, wrapperProps: { client: createQueryClient() } }
		);

		await page.getByLabelText('Your answer for Services').getByText('Needs a change').click();
		// A change without words yet is not kept; the box asks for them.
		expect(noteSaves(fetch)).toEqual([]);

		await page.getByLabelText('What should change?').fill('Add Dhamrai to our towns.');
		await expect
			.poll(() => noteSaves(fetch).at(-1), { timeout: 3000 })
			.toMatchObject({ card_id: 'c1', choice: 'needs_change', note: 'Add Dhamrai to our towns.' });
		await expect.element(page.getByText('Saved', { exact: true })).toBeVisible();
	});
});
