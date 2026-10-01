import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import OpportunityCard from './OpportunityCard.svelte';
import type { OpportunityCard as OpportunityCardData } from '$lib/pipeline/api';

vi.mock('@tanstack/svelte-query', async (importOriginal) => ({
	...(await importOriginal<typeof import('@tanstack/svelte-query')>()),
	useQueryClient: () => ({ prefetchQuery: vi.fn() }),
	// An editable card mounts the owner control, which reads the team list. Nothing here is about owners.
	createQuery: () => ({ data: undefined, isPending: true, isError: false }),
	createMutation: () => ({ mutate: vi.fn(), isPending: false })
}));

const card: OpportunityCardData = {
	id: 'opportunity-1',
	title: 'Kitchen remodel',
	stage: 'assessment_unscheduled',
	custom_stage_id: null,
	stage_entered_at: '2026-08-23T00:00:00.000Z',
	outcome: 'open',
	created_at: '2026-08-23T00:00:00.000Z',
	request: { id: 'request-1', status: 'assessment_unscheduled' },
	quote: null,
	client: null,
	property: null,
	owner: null,
	expected_close_on: null,
	next_follow_up_on: null,
	task: null,
	assessment: null
};

describe('OpportunityCard keyboard open', () => {
	// PipelineColumn narrows svelte-dnd-action's keyboard-drag trigger to Space, precisely so this
	// control keeps Enter for itself. If a future change reclaims Space here, the same press would both
	// open the Brief and start a keyboard drag on a draggable card.
	it('opens on Enter but leaves Space to the board keyboard-drag trigger', async () => {
		const onOpen = vi.fn();
		// canEdit: false keeps the owner field (its own live query) out of the tree -- irrelevant to the
		// keyboard behavior under test, and it would otherwise need a real QueryClientProvider.
		render(OpportunityCard, {
			props: { opportunity: card, formatting: null, canEdit: false, onOpen }
		});

		const open = page.getByLabelText('Open Kitchen remodel for No client');
		await open.element().focus();

		await open.element().dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }));
		expect(onOpen).not.toHaveBeenCalled();

		await open
			.element()
			.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
		expect(onOpen).toHaveBeenCalledOnce();
	});
});

describe('OpportunityCard delivery failure', () => {
	// The quote stays sent and the card stays in Awaiting response; the card only has to say, in words,
	// that the customer has nothing yet.
	it('says "Delivery failed" when the quote email did not reach the customer', async () => {
		render(OpportunityCard, {
			props: {
				opportunity: {
					...card,
					stage: 'quote_awaiting_response',
					request: null,
					quote: {
						id: 'quote-1',
						status: 'awaiting_response',
						delivery_failure: {
							reason: 'bounced',
							failed_at: '2026-10-01T09:00:00.000Z',
							recipient_email: 'ada@example.com'
						}
					}
				},
				formatting: null,
				canEdit: false,
				onOpen: vi.fn()
			}
		});

		await expect.element(page.getByText('Delivery failed')).toBeVisible();
	});

	it('says nothing about delivery for a quote that was delivered', async () => {
		render(OpportunityCard, {
			props: {
				opportunity: {
					...card,
					stage: 'quote_awaiting_response',
					request: null,
					quote: { id: 'quote-1', status: 'awaiting_response', delivery_failure: null }
				},
				formatting: null,
				canEdit: false,
				onOpen: vi.fn()
			}
		});

		await expect.element(page.getByText('Delivery failed')).not.toBeInTheDocument();
	});
});

describe('OpportunityCard Mark as lost', () => {
	const quoteCard = (stage: OpportunityCardData['stage'], status: string): OpportunityCardData => ({
		...card,
		stage,
		request: null,
		quote: { id: 'quote-1', status, delivery_failure: null }
	});

	function renderCard(opportunity: OpportunityCardData) {
		render(OpportunityCard, {
			props: { opportunity, formatting: null, canEdit: true, onOpen: vi.fn() }
		});
	}

	// A quote the customer has seen can be lost; the dialog says what happens to the quote, not a request.
	it('offers it on a sent quote and says the quote will be archived', async () => {
		renderCard(quoteCard('quote_awaiting_response', 'awaiting_response'));

		await page.getByRole('button', { name: 'More actions for Kitchen remodel' }).click();
		await page.getByRole('menuitem', { name: 'Mark as lost' }).click();

		await expect
			.element(page.getByText(/This quote will leave the board and be archived/))
			.toBeVisible();
	});

	// A draft nobody received is not lost. With no custom stages either, the card has no menu at all.
	it('does not offer it on a draft quote', async () => {
		renderCard(quoteCard('quote_draft', 'draft'));

		await expect
			.element(page.getByRole('button', { name: 'More actions for Kitchen remodel' }))
			.not.toBeInTheDocument();
	});
});
