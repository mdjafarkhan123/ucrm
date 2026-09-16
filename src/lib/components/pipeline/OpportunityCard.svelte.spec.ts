import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import OpportunityCard from './OpportunityCard.svelte';
import type { OpportunityCard as OpportunityCardData } from '$lib/pipeline/api';

vi.mock('@tanstack/svelte-query', async (importOriginal) => ({
	...(await importOriginal<typeof import('@tanstack/svelte-query')>()),
	useQueryClient: () => ({ prefetchQuery: vi.fn() })
}));

const card: OpportunityCardData = {
	id: 'opportunity-1',
	title: 'Kitchen remodel',
	stage: 'assessment_unscheduled',
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
