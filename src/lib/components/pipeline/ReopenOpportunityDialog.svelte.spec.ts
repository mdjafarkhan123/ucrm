import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import ReopenOpportunityDialog from './ReopenOpportunityDialog.svelte';
import type { OutcomeCommandResult } from '$lib/pipeline/api';

// Reopen's only UI entry point (4C): a required short explanation, disabled Reopen until one is typed,
// and the dialog stays actionable on failure the same way MarkOpportunityLostDialog's does.

const opportunityId = 'opp-1';

function renderDialog(onSaved = vi.fn(), onClose = vi.fn()) {
	const screen = render(ReopenOpportunityDialog, {
		props: { open: true, opportunityId, onSaved, onClose }
	});
	return { screen, onSaved, onClose };
}

const originalFetch = globalThis.fetch;

function mockFetch(response: { body: unknown; status: number }) {
	globalThis.fetch = vi.fn(() =>
		Promise.resolve(new Response(JSON.stringify(response.body), { status: response.status }))
	);
}

const result: OutcomeCommandResult = {
	applied: true,
	event_id: 'event-1',
	outcome: 'open',
	outcome_at: null
};

describe('ReopenOpportunityDialog', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('disables Reopen until an explanation is typed, then sends it', async () => {
		mockFetch({ body: result, status: 200 });
		const { onSaved } = renderDialog();

		await expect.element(page.getByRole('button', { name: 'Reopen' })).toBeDisabled();

		await page.getByRole('textbox', { name: /Why is this reopening/ }).fill('Client came back');

		await expect.element(page.getByRole('button', { name: 'Reopen' })).not.toBeDisabled();

		await page.getByRole('button', { name: 'Reopen' }).click();

		expect(globalThis.fetch).toHaveBeenCalledWith(
			`/api/pipeline/opportunities/${opportunityId}/reopen`,
			expect.objectContaining({ method: 'POST' })
		);
		const [, init] = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
		const sent = JSON.parse(init.body as string);
		expect(sent.reopen_explanation).toBe('Client came back');
		expect(sent.idempotency_key).toMatch(/^[0-9a-f-]{36}$/);
		await vi.waitFor(() => expect(onSaved).toHaveBeenCalledWith(result));
	});

	it('shows a state refusal under the form rather than rewriting it', async () => {
		mockFetch({
			body: {
				error: 'Refused',
				field_errors: { form: 'Only a lost opportunity can be reopened.' }
			},
			status: 422
		});
		const { onSaved } = renderDialog();

		await page.getByRole('textbox', { name: /Why is this reopening/ }).fill('Client came back');
		await page.getByRole('button', { name: 'Reopen' }).click();

		await expect.element(page.getByText('Only a lost opportunity can be reopened.')).toBeVisible();
		expect(onSaved).not.toHaveBeenCalled();
	});

	it('keeps the row actionable on failure', async () => {
		mockFetch({ body: { error: 'Something went wrong' }, status: 500 });
		const { onClose } = renderDialog();

		await page.getByRole('textbox', { name: /Why is this reopening/ }).fill('Client came back');
		await page.getByRole('button', { name: 'Reopen' }).click();

		await expect.element(page.getByText('Something went wrong')).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Reopen' })).not.toBeDisabled();
		expect(onClose).not.toHaveBeenCalled();
	});
});
