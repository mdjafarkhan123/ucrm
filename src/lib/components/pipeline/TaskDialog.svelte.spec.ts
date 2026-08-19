import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import TaskDialog from './TaskDialog.svelte';
import type { Task } from '$lib/pipeline/api';

// The create/edit form: one shape for both, sends all four fields together, and shows a limit or
// assignee refusal as the sentence the server wrote for it rather than a rewritten one — see the Task
// write contract in `docs/sales-pipeline-behavior-contract.md`.

const task: Task = {
	id: 'task-1',
	opportunity_id: 'opp-1',
	title: 'Call Colin',
	instructions: null,
	assignee_user_id: null,
	due_on: '2026-09-05',
	status: 'open',
	completed_at: null,
	completed_by: null,
	created_at: '2026-08-10T00:00:00.000Z'
};

function renderDialog(props: { task?: Task | null } = {}, onSaved = vi.fn(), onClose = vi.fn()) {
	const queryClient = createQueryClient();
	const screen = render(
		TaskDialog,
		{
			props: { open: true, opportunityId: 'opp-1', task: props.task ?? null, onSaved, onClose }
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
	return { screen, onSaved, onClose };
}

const originalFetch = globalThis.fetch;

function mockFetch(taskResponse: { body: unknown; status: number }) {
	globalThis.fetch = vi.fn((input: RequestInfo | URL) => {
		const url = String(input);
		if (url.includes('/team/assignable')) {
			return Promise.resolve(new Response(JSON.stringify({ members: [] }), { status: 200 }));
		}
		return Promise.resolve(
			new Response(JSON.stringify(taskResponse.body), { status: taskResponse.status })
		);
	});
}

describe('TaskDialog', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('creates a task with the typed title and hands the saved row back', async () => {
		mockFetch({ body: task, status: 201 });
		const { onSaved } = renderDialog();

		await page.getByRole('textbox', { name: 'Title' }).fill('Call Colin');
		await page.getByRole('button', { name: 'Add task' }).click();

		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/api/pipeline/opportunities/opp-1/tasks',
			expect.objectContaining({
				method: 'POST',
				body: JSON.stringify({
					title: 'Call Colin',
					instructions: null,
					assignee_user_id: null,
					due_on: null
				})
			})
		);
		await vi.waitFor(() => expect(onSaved).toHaveBeenCalledWith(task));
	});

	it('disables Add task until a title is typed', async () => {
		mockFetch({ body: task, status: 201 });
		renderDialog();

		await expect.element(page.getByRole('button', { name: 'Add task' })).toBeDisabled();
	});

	it('pre-fills an edit and sends a PATCH to that task', async () => {
		mockFetch({ body: { ...task, title: 'Call Colin back' }, status: 200 });
		const { onSaved } = renderDialog({ task });

		await expect.element(page.getByRole('textbox', { name: 'Title' })).toHaveValue('Call Colin');
		await page.getByRole('textbox', { name: 'Title' }).fill('Call Colin back');
		await page.getByRole('button', { name: 'Save' }).click();

		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/api/pipeline/tasks/task-1',
			expect.objectContaining({ method: 'PATCH' })
		);
		await vi.waitFor(() => expect(onSaved).toHaveBeenCalled());
	});

	it('shows a limit refusal under the form rather than rewriting it', async () => {
		mockFetch({
			body: {
				error: 'Refused',
				field_errors: { form: 'This opportunity already has five open tasks.' }
			},
			status: 422
		});
		const { onSaved } = renderDialog();

		await page.getByRole('textbox', { name: 'Title' }).fill('One too many');
		await page.getByRole('button', { name: 'Add task' }).click();

		await expect
			.element(page.getByText('This opportunity already has five open tasks.'))
			.toBeVisible();
		expect(onSaved).not.toHaveBeenCalled();
	});

	it('shows an ineligible-assignee refusal under the Owner field', async () => {
		mockFetch({
			body: {
				error: 'Refused',
				field_errors: {
					assignee_user_id: 'That person cannot be given work on the sales pipeline.'
				}
			},
			status: 422
		});
		renderDialog();

		await page.getByRole('textbox', { name: 'Title' }).fill('Call Colin');
		await page.getByRole('button', { name: 'Add task' }).click();

		await expect
			.element(page.getByText('That person cannot be given work on the sales pipeline.'))
			.toBeVisible();
	});
});
