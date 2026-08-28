import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import OpportunityTasksSection from './OpportunityTasksSection.svelte';
import type { BoardFormatting } from '$lib/pipeline/money';

// The Brief's Tasks block: the open list in card-priority order, a struck-through completed section, and
// the complete/reopen checkbox — see `docs/sales-pipeline-behavior-contract.md`.

const formatting: BoardFormatting = {
	currency_code: 'USD',
	locale: 'en-US',
	timezone: 'America/Toronto'
};

function taskFixture(overrides: Record<string, unknown> = {}) {
	return {
		id: 'task-1',
		opportunity_id: 'opp-1',
		title: 'Call Colin',
		instructions: null,
		assignee_user_id: null,
		due_on: null,
		status: 'open',
		completed_at: null,
		completed_by: null,
		created_at: '2026-08-10T00:00:00.000Z',
		...overrides
	};
}

function renderSection(props: { canEdit?: boolean } = {}) {
	const queryClient = createQueryClient();
	return render(
		OpportunityTasksSection,
		{
			props: { opportunityId: 'opp-1', formatting, canEdit: props.canEdit ?? true }
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
}

const originalFetch = globalThis.fetch;

function mockFetch(tasksBody: { open: unknown[]; completed: unknown[] }) {
	globalThis.fetch = vi.fn((input: RequestInfo | URL) => {
		const url = String(input);
		if (url.includes('/tasks') && !url.includes('completion')) {
			return Promise.resolve(new Response(JSON.stringify(tasksBody), { status: 200 }));
		}
		if (url.includes('/completion')) {
			return Promise.resolve(
				new Response(JSON.stringify({ ...taskFixture(), status: 'completed' }), { status: 200 })
			);
		}
		if (url.includes('/team/assignable')) {
			return Promise.resolve(new Response(JSON.stringify({ members: [] }), { status: 200 }));
		}
		return Promise.resolve(new Response(JSON.stringify({}), { status: 200 }));
	});
}

describe('OpportunityTasksSection', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('shows the empty state and an Add task action', async () => {
		mockFetch({ open: [], completed: [] });
		renderSection();

		await expect.element(page.getByText('No tasks yet')).toBeVisible();
		await expect.element(page.getByRole('button', { name: '+ Add task' })).toBeVisible();
	});

	it('lists open Tasks and a struck-through COMPLETED section', async () => {
		mockFetch({
			open: [taskFixture({ due_on: '2026-08-01' })],
			completed: [taskFixture({ id: 'task-2', title: 'Follow up', status: 'completed' })]
		});
		renderSection();

		await expect.element(page.getByText('Call Colin', { exact: true })).toBeVisible();
		await expect.element(page.getByText('Overdue')).toBeVisible();
		await expect.element(page.getByText('COMPLETED · 1')).toBeVisible();
		await expect.element(page.getByText('Follow up', { exact: true })).toBeVisible();
		await expect.element(page.getByRole('checkbox', { name: 'Reopen "Follow up"' })).toBeChecked();
	});

	it('completes an open Task through the completion route when its checkbox is checked', async () => {
		mockFetch({ open: [taskFixture()], completed: [] });
		renderSection();

		// The native input is visually hidden behind the custom `.checkbox__box`, so the click lands on the
		// visible label text -- a real click there toggles the associated input the same way.
		await page.getByText('Mark "Call Colin" complete', { exact: true }).click();

		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/api/pipeline/tasks/task-1/completion',
			expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ completed: true }) })
		);
	});

	it('hides Add task and every row menu for a read-only member', async () => {
		mockFetch({ open: [taskFixture()], completed: [] });
		renderSection({ canEdit: false });

		await expect.element(page.getByText('Call Colin', { exact: true })).toBeVisible();
		expect(page.getByRole('button', { name: '+ Add task' }).elements()).toHaveLength(0);
		expect(
			page.getByRole('button', { name: 'Task actions for Call Colin' }).elements()
		).toHaveLength(0);
		await expect
			.element(page.getByRole('checkbox', { name: 'Mark "Call Colin" complete' }))
			.toBeDisabled();
	});
});
