import { page, userEvent } from 'vitest/browser';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import OpportunityDetailsSection from './OpportunityDetailsSection.svelte';
import type { OpportunityCard } from '$lib/pipeline/api';
import type { BoardFormatting } from '$lib/pipeline/money';

// The Brief's edit flow: a pencil opens a row in place, the estimated value commits on blur or Enter and
// reverts on Escape, and a failed write shows inline on its own row rather than a toast — see item 7 in
// `Memory/campaigns/sales-pipeline/parts/02-ownership-value-dates-sort-filter.md`.

const opportunity: OpportunityCard = {
	id: 'opp-1',
	title: 'Rewire the panel',
	stage: 'new_request',
	stage_entered_at: '2026-08-10T00:00:00.000Z',
	outcome: 'open',
	created_at: '2026-08-10T00:00:00.000Z',
	request: { id: 'req-1', status: 'new' },
	client: { id: 'client-1', display_name: 'Ada Lovelace', company_name: null },
	property: null,
	owner: null,
	estimated_value: null,
	expected_close_on: null,
	next_follow_up_on: null,
	task: null
};

const formatting: BoardFormatting = {
	currency_code: 'USD',
	locale: 'en-US',
	timezone: 'America/Toronto'
};

function renderSection(onUpdate = vi.fn()) {
	const queryClient = createQueryClient();
	const screen = render(
		OpportunityDetailsSection,
		{ props: { opportunity, formatting, canEdit: true, onUpdate } },
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
	return { screen, onUpdate };
}

const originalFetch = globalThis.fetch;

// One Response body can only be read once, so a shared `mockResolvedValue` breaks the moment two calls
// (here, the Salesperson field's own team-list fetch and the value PATCH) race to read it. Each mock
// below builds a fresh Response per call instead.
function mockFetch(valueResponse: { body: unknown; status: number }) {
	globalThis.fetch = vi.fn((input: RequestInfo | URL) => {
		const url = String(input);
		if (url.endsWith('/value')) {
			return Promise.resolve(
				new Response(JSON.stringify(valueResponse.body), { status: valueResponse.status })
			);
		}
		return Promise.resolve(new Response(JSON.stringify({ members: [] }), { status: 200 }));
	});
}

describe('OpportunityDetailsSection value edit', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('saves a typed value on blur, closes the editor, and hands the new value to onUpdate', async () => {
		mockFetch({ body: { id: 'opp-1', estimated_value: 4200 }, status: 200 });
		const { screen, onUpdate } = renderSection();

		await page.getByRole('button', { name: 'Edit estimated value' }).click();
		const input = page.getByRole('textbox', { name: 'Estimated value' });
		await input.fill('4200');
		await input.element().dispatchEvent(new FocusEvent('blur'));

		// The row closes back to its read view — this component never assumes its own success; the parent
		// re-renders it with the patched opportunity, which is what actually shows the new amount.
		await expect.element(page.getByRole('button', { name: 'Edit estimated value' })).toBeVisible();
		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/api/pipeline/opportunities/opp-1/value',
			expect.objectContaining({
				method: 'PATCH',
				body: JSON.stringify({ estimated_value: 4200 })
			})
		);
		expect(onUpdate).toHaveBeenCalledWith({ estimated_value: 4200 });

		// Simulate the parent applying the patch via `onUpdate`, the way `+page.svelte` really does.
		await screen.rerender({ opportunity: { ...opportunity, estimated_value: 4200 } });
		await expect.element(page.getByText('$4,200')).toBeVisible();
	});

	it('reverts without saving on Escape', async () => {
		mockFetch({ body: {}, status: 200 });
		const { onUpdate } = renderSection();

		await page.getByRole('button', { name: 'Edit estimated value' }).click();
		const input = page.getByRole('textbox', { name: 'Estimated value' });
		await input.fill('999');
		await userEvent.keyboard('{Escape}');

		await expect.element(page.getByText('Not estimated yet')).toBeVisible();
		const valueCalls = vi
			.mocked(globalThis.fetch)
			.mock.calls.filter(([url]) => url === '/api/pipeline/opportunities/opp-1/value');
		expect(valueCalls).toHaveLength(0);
		expect(onUpdate).not.toHaveBeenCalled();
	});

	it('shows a failed write inline on the row instead of a toast', async () => {
		mockFetch({ body: { error: 'The estimated value could not be updated.' }, status: 500 });
		const { onUpdate } = renderSection();

		await page.getByRole('button', { name: 'Edit estimated value' }).click();
		const input = page.getByRole('textbox', { name: 'Estimated value' });
		await input.fill('500');
		await input.element().dispatchEvent(new FocusEvent('blur'));

		await expect.element(page.getByText('The estimated value could not be updated.')).toBeVisible();
		// The field stays open with the retryable value visible, not reset or hidden behind a toast.
		await expect.element(input).toHaveValue('500');
		expect(onUpdate).not.toHaveBeenCalled();
	});
});
