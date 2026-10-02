import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClient } from '@tanstack/query-core';
import { QueryClientProvider } from '@tanstack/svelte-query';
import OpportunityCallsSection from './OpportunityCallsSection.svelte';
import { opportunityCallsKey } from '$lib/pipeline/api';
import { assignableTeamKey } from '$lib/team/api';

vi.mock('$lib/components/ui/ToastManager.svelte', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/components/ui/ToastManager.svelte')>()),
	getToastManager: () => ({ success: vi.fn(), error: vi.fn() })
}));

// The Brief's Calls block. A call is logged only when a person taps an outcome -- nothing is chosen for them --
// and only a call that reached the customer tells the Brief the clock restarted.

const opportunityId = 'opp-1';
const formatting = { currency_code: 'USD', locale: 'en-US', timezone: 'America/Chicago' };
const originalFetch = globalThis.fetch;

function renderSection(props: Record<string, unknown> = {}, calls: unknown[] = []) {
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	queryClient.setQueryData(opportunityCallsKey(opportunityId), calls);
	queryClient.setQueryData(assignableTeamKey, [
		{ id: 'user-1', full_name: 'Sam Rivera', avatar_url: null }
	]);
	const onLogged = vi.fn();
	const screen = render(
		OpportunityCallsSection,
		{
			props: {
				opportunityId,
				clientName: 'Colin Smith',
				formatting,
				canEdit: true,
				logOpen: true,
				currentUserId: 'user-1',
				onLogged,
				...props
			} as never
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } } as never
	);
	return { screen, onLogged };
}

function mockFetch(restarted: boolean) {
	globalThis.fetch = vi.fn((_url: unknown, init?: RequestInit) =>
		Promise.resolve(
			init?.method === 'POST'
				? new Response(
						JSON.stringify({
							id: 'call-1',
							opportunity_id: opportunityId,
							outcome: 'connected',
							note: null,
							logged_by: 'user-1',
							created_at: '2026-10-02T10:00:00Z',
							restarted_progress: restarted
						}),
						{ status: 201 }
					)
				: new Response(JSON.stringify({ calls: [] }), { status: 200 })
		)
	) as never;
}

describe('OpportunityCallsSection', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('asks how the call went and records nothing until an outcome is tapped', async () => {
		mockFetch(true);
		renderSection();

		await expect.element(page.getByText('How did the call go?')).toBeVisible();
		for (const label of ['Connected', 'Left voicemail', 'No answer', 'Busy', 'Wrong number']) {
			await expect.element(page.getByRole('button', { name: label, exact: true })).toBeVisible();
		}
		expect(globalThis.fetch).not.toHaveBeenCalledWith(
			expect.stringContaining('/calls'),
			expect.objectContaining({ method: 'POST' })
		);
	});

	it('logs the tapped outcome with no note by default, and tells the Brief the clock restarted', async () => {
		mockFetch(true);
		const { onLogged } = renderSection();

		await page.getByRole('button', { name: 'Connected', exact: true }).click();

		await vi.waitFor(() => expect(onLogged).toHaveBeenCalledWith(true));
		const post = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls.find(
			([, init]) => init?.method === 'POST'
		);
		expect(post?.[0]).toBe(`/api/pipeline/opportunities/${opportunityId}/calls`);
		expect(JSON.parse(post?.[1].body as string)).toEqual({ outcome: 'connected', note: null });
	});

	it('sends the note typed before the outcome was tapped', async () => {
		mockFetch(false);
		renderSection();

		await page.getByRole('button', { name: '+ Add a note' }).click();
		await page.getByRole('textbox', { name: /Note/ }).fill('Call back after 5');
		await page.getByRole('button', { name: 'No answer', exact: true }).click();

		await vi.waitFor(() => {
			const post = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls.find(
				([, init]) => init?.method === 'POST'
			);
			expect(JSON.parse(post?.[1].body as string)).toEqual({
				outcome: 'no_answer',
				note: 'Call back after 5'
			});
		});
	});

	it('offers a try-again Task after a call that did not get through, and the Brief is told the clock did not restart', async () => {
		mockFetch(false);
		const { onLogged } = renderSection();

		await page.getByRole('button', { name: 'Busy', exact: true }).click();

		await expect.element(page.getByText('Try again tomorrow?')).toBeVisible();
		expect(onLogged).toHaveBeenCalledWith(false);
	});

	it('does not offer a try-again Task after a wrong number', async () => {
		mockFetch(false);
		const { onLogged } = renderSection();

		await page.getByRole('button', { name: 'Wrong number', exact: true }).click();

		await vi.waitFor(() => expect(onLogged).toHaveBeenCalled());
		await expect.element(page.getByText('Try again tomorrow?')).not.toBeInTheDocument();
	});

	it('lets a member who cannot edit read the calls but not log one', async () => {
		renderSection({ canEdit: false }, [
			{
				id: 'call-1',
				opportunity_id: opportunityId,
				outcome: 'left_voicemail',
				note: 'Asked for a callback',
				logged_by: 'user-1',
				created_at: '2026-10-02T10:00:00Z'
			}
		]);

		await expect.element(page.getByText('Left voicemail')).toBeVisible();
		await expect.element(page.getByText('Asked for a callback')).toBeVisible();
		await expect.element(page.getByText(/Sam Rivera/)).toBeVisible();
		await expect.element(page.getByText('How did the call go?')).not.toBeInTheDocument();
		await expect.element(page.getByRole('button', { name: '+ Log call' })).not.toBeInTheDocument();
	});
});
