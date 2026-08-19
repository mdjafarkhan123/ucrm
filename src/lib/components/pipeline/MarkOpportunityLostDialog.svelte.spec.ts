import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import MarkOpportunityLostDialog from './MarkOpportunityLostDialog.svelte';
import type { OutcomeCommandResult } from '$lib/pipeline/api';

// The card's Mark as lost action: reason and note are both optional except "Other", which requires a
// note before the database is even asked — see 4B's packet and the RPC's own mirrored check.

const opportunityId = 'opp-1';

function renderDialog(onSaved = vi.fn(), onClose = vi.fn()) {
	const screen = render(MarkOpportunityLostDialog, {
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
	outcome: 'lost',
	outcome_at: '2026-08-19T00:00:00.000Z'
};

describe('MarkOpportunityLostDialog', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('submits with no reason and no note by default', async () => {
		mockFetch({ body: result, status: 200 });
		const { onSaved } = renderDialog();

		await page.getByRole('button', { name: 'Mark as lost' }).click();

		expect(globalThis.fetch).toHaveBeenCalledWith(
			`/api/pipeline/opportunities/${opportunityId}/lost`,
			expect.objectContaining({ method: 'POST' })
		);
		const [, init] = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
		const sent = JSON.parse(init.body as string);
		expect(sent.reason).toBeNull();
		expect(sent.note).toBeNull();
		expect(sent.idempotency_key).toMatch(/^[0-9a-f-]{36}$/);
		await vi.waitFor(() => expect(onSaved).toHaveBeenCalledWith(result));
	});

	it('disables Mark as lost once "Other" is chosen until a note is typed', async () => {
		mockFetch({ body: result, status: 200 });
		renderDialog();

		await expect.element(page.getByRole('button', { name: 'Mark as lost' })).not.toBeDisabled();

		await page.getByLabelText('Reason (optional)').click();
		await page.getByRole('option', { name: 'Other', exact: true }).click();

		await expect.element(page.getByRole('button', { name: 'Mark as lost' })).toBeDisabled();

		await page.getByRole('textbox', { name: /Note/ }).fill('Turned out to be a duplicate');

		await expect.element(page.getByRole('button', { name: 'Mark as lost' })).not.toBeDisabled();

		await page.getByRole('button', { name: 'Mark as lost' }).click();

		const [, init] = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
		const sent = JSON.parse(init.body as string);
		expect(sent.reason).toBe('other');
		expect(sent.note).toBe('Turned out to be a duplicate');
	});

	it('shows a state refusal under the form rather than rewriting it', async () => {
		mockFetch({
			body: {
				error: 'Refused',
				field_errors: { form: 'Only an open opportunity can be marked lost.' }
			},
			status: 422
		});
		const { onSaved } = renderDialog();

		await page.getByRole('button', { name: 'Mark as lost' }).click();

		await expect
			.element(page.getByText('Only an open opportunity can be marked lost.'))
			.toBeVisible();
		expect(onSaved).not.toHaveBeenCalled();
	});

	it('keeps the card in place and the dialog actionable on failure', async () => {
		mockFetch({ body: { error: 'Something went wrong' }, status: 500 });
		const { onClose } = renderDialog();

		await page.getByRole('button', { name: 'Mark as lost' }).click();

		await expect.element(page.getByText('Something went wrong')).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Mark as lost' })).not.toBeDisabled();
		expect(onClose).not.toHaveBeenCalled();
	});
});
