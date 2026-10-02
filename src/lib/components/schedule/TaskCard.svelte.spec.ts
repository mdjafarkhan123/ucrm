import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import { taskToItem } from '$lib/schedule/items';
import type { ScheduleTask } from '$lib/schedule/api';
import TaskCard from './TaskCard.svelte';

// The card reports its outcome through the shared toast manager, which the app shell provides; here there
// is no shell, so a stub stands in and nothing asserts on it.
vi.mock('$lib/components/ui/ToastManager.svelte', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/components/ui/ToastManager.svelte')>()),
	getToastManager: () => ({ success: vi.fn(), error: vi.fn() })
}));

// A Pipeline Task on the calendar: the card opens the Task's card, and its box ticks the Task off without
// leaving the calendar — see `docs/sales-pipeline-behavior-contract.md`.

const TODAY = '2026-10-09';

function renderCard(overrides: Partial<ScheduleTask> = {}) {
	const task: ScheduleTask = {
		id: 'task-1',
		opportunity_id: 'opp-1',
		title: 'Call Mr. Ali',
		due_on: TODAY,
		completed_at: null,
		assignee_user_id: null,
		opportunity_open: true,
		can_complete: true,
		request_id: 'req-1',
		quote_id: null,
		client_name: 'Ali Raza',
		client_company_name: null,
		...overrides
	};
	return render(
		TaskCard,
		{
			props: { task: taskToItem(task), density: 'standard', today: TODAY, employeesById: new Map() }
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: createQueryClient() } }
	);
}

const originalFetch = globalThis.fetch;

function mockCompletion() {
	const calls: { url: string; body: unknown }[] = [];
	globalThis.fetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
		calls.push({ url: String(input), body: init?.body ? JSON.parse(String(init.body)) : null });
		return Promise.resolve(new Response(JSON.stringify({ id: 'task-1' }), { status: 200 }));
	}) as typeof fetch;
	return calls;
}

afterEach(() => {
	globalThis.fetch = originalFetch;
});

describe('TaskCard', () => {
	it('ticks an open Task off from the calendar', async () => {
		const calls = mockCompletion();
		renderCard();

		await page.getByRole('button', { name: 'Mark "Call Mr. Ali" complete' }).click();

		await vi.waitFor(() =>
			expect(calls.find((call) => call.url.includes('/completion'))).toEqual({
				url: '/api/pipeline/tasks/task-1/completion',
				body: { completed: true }
			})
		);
	});

	it('still opens the Task from anywhere else on the card', async () => {
		renderCard();

		await expect
			.element(page.getByRole('link', { name: /Call Mr\. Ali/ }))
			.toHaveAttribute('href', expect.stringContaining('brief=opp-1'));
	});

	it('reopens a finished Task while its card is still on the board', async () => {
		const calls = mockCompletion();
		renderCard({ completed_at: '2026-10-09T10:00:00.000Z' });

		await page.getByRole('button', { name: 'Reopen "Call Mr. Ali"' }).click();

		await vi.waitFor(() =>
			expect(calls.find((call) => call.url.includes('/completion'))?.body).toEqual({
				completed: false
			})
		);
	});

	it('lets an open Task on a card that has left the board be ticked off', async () => {
		renderCard({ opportunity_open: false });

		await expect
			.element(page.getByRole('button', { name: 'Mark "Call Mr. Ali" complete' }))
			.toBeInTheDocument();
	});

	it('offers no box for a finished Task on a card that has left the board', async () => {
		renderCard({ opportunity_open: false, completed_at: '2026-10-09T10:00:00.000Z' });

		await expect.element(page.getByRole('link', { name: /Call Mr\. Ali/ })).toBeInTheDocument();
		expect(page.getByRole('button').elements()).toHaveLength(0);
	});

	it('offers no box to a member who may not edit the Pipeline', async () => {
		renderCard({ can_complete: false });

		await expect.element(page.getByRole('link', { name: /Call Mr\. Ali/ })).toBeInTheDocument();
		expect(page.getByRole('button').elements()).toHaveLength(0);
	});
});
