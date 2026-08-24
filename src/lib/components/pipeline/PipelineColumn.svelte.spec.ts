import { page } from 'vitest/browser';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import PipelineColumn from './PipelineColumn.svelte';
import { DEFAULT_BOARD_FILTERS } from '$lib/pipeline/filters';
import type { OpportunityCard } from '$lib/pipeline/api';
import type { AnyBoardStage } from '$lib/pipeline/stages';

const mocks = vi.hoisted(() => ({
	dragOpportunity: vi.fn(),
	invalidatePipeline: vi.fn(),
	toast: {
		loading: vi.fn(() => 41),
		dismiss: vi.fn(),
		success: vi.fn(),
		error: vi.fn()
	},
	query: {
		data: { pages: [{ opportunities: [], next_cursor: null }] },
		isPending: false,
		isError: false,
		hasNextPage: false,
		isFetchingNextPage: false,
		fetchNextPage: vi.fn()
	}
}));

vi.mock('@tanstack/svelte-query', async (importOriginal) => ({
	...(await importOriginal<typeof import('@tanstack/svelte-query')>()),
	createInfiniteQuery: () => mocks.query,
	useQueryClient: () => ({})
}));

vi.mock('$lib/components/ui/ToastManager.svelte', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/components/ui/ToastManager.svelte')>()),
	getToastManager: () => mocks.toast
}));

vi.mock('$lib/pipeline/api', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/pipeline/api')>()),
	dragOpportunity: mocks.dragOpportunity,
	invalidatePipeline: mocks.invalidatePipeline
}));

const card: OpportunityCard = {
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

function renderColumn(stage: AnyBoardStage) {
	const onDragBusyChange = vi.fn();
	const screen = render(PipelineColumn, {
		props: {
			stage,
			count: 0,
			valueTotal: null,
			filters: DEFAULT_BOARD_FILTERS,
			formatting: null,
			canEdit: true,
			onOpen: vi.fn(),
			draggingFromStage: card.stage,
			onDragStageChange: vi.fn(),
			dragBusy: false,
			onDragBusyChange
		}
	});
	const zone = screen.container.querySelector('.pipeline-column__cards');
	if (!zone) throw new Error('Drop zone did not render.');
	return { screen, zone, onDragBusyChange };
}

function finalize(zone: Element) {
	zone.dispatchEvent(
		new CustomEvent('finalize', {
			detail: {
				items: [card],
				info: { id: card.id, trigger: 'droppedIntoZone', source: 'pointer' }
			}
		})
	);
}

describe('PipelineColumn drop confirmation', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mocks.dragOpportunity.mockResolvedValue({
			id: card.id,
			from_stage: card.stage,
			to_stage: 'assessment_completed'
		});
		mocks.invalidatePipeline.mockResolvedValue(undefined);
	});

	it('restores a refused backward drop without calling the server or showing a toast', async () => {
		const { zone } = renderColumn('new_request');

		finalize(zone);

		await expect.element(page.getByText('Nothing here.')).toBeVisible();
		expect(mocks.dragOpportunity).not.toHaveBeenCalled();
		expect(mocks.toast.loading).not.toHaveBeenCalled();
	});

	it('waits for Schedule confirmation before showing saving feedback or calling the server', async () => {
		const { zone, onDragBusyChange } = renderColumn('assessment_scheduled');

		finalize(zone);

		await expect.element(page.getByRole('dialog')).toBeVisible();
		await expect.element(page.getByText('Schedule the assessment - Kitchen remodel')).toBeVisible();
		expect(mocks.dragOpportunity).not.toHaveBeenCalled();
		expect(mocks.toast.loading).not.toHaveBeenCalled();
		expect(onDragBusyChange).toHaveBeenCalledWith(true);
	});

	it('keeps the destination empty and reports success only after the server and refresh finish', async () => {
		let finishServer!: () => void;
		let finishRefresh!: () => void;
		mocks.dragOpportunity.mockImplementation(
			() => new Promise((resolve) => (finishServer = () => resolve({})))
		);
		mocks.invalidatePipeline.mockImplementation(
			() => new Promise((resolve) => (finishRefresh = () => resolve(undefined)))
		);
		const { zone, onDragBusyChange } = renderColumn('assessment_completed');

		finalize(zone);

		await expect.element(page.getByText('Nothing here.')).toBeVisible();
		expect(mocks.dragOpportunity).toHaveBeenCalledWith(card.id, {
			toStage: 'assessment_completed',
			startsAt: undefined,
			endsAt: undefined
		});
		expect(mocks.toast.loading).toHaveBeenCalledWith('Saving change…');
		expect(mocks.toast.success).not.toHaveBeenCalled();
		expect(onDragBusyChange).toHaveBeenCalledWith(true);

		finishServer();
		await vi.waitFor(() => expect(mocks.invalidatePipeline).toHaveBeenCalledOnce());
		expect(mocks.toast.success).not.toHaveBeenCalled();

		finishRefresh();
		await vi.waitFor(() => expect(mocks.toast.success).toHaveBeenCalledWith('Change saved.'));
		expect(mocks.toast.dismiss).toHaveBeenCalledWith(41);
		expect(onDragBusyChange).toHaveBeenLastCalledWith(false);
	});

	it('refreshes truth and replaces loading feedback with an error when the server refuses', async () => {
		mocks.dragOpportunity.mockRejectedValue(new Error('The move is no longer allowed.'));
		const { zone, onDragBusyChange } = renderColumn('assessment_completed');

		finalize(zone);

		await vi.waitFor(() =>
			expect(mocks.toast.error).toHaveBeenCalledWith(
				'That card could not be moved.',
				'The move is no longer allowed.'
			)
		);
		expect(mocks.invalidatePipeline).toHaveBeenCalledOnce();
		expect(mocks.toast.dismiss).toHaveBeenCalledWith(41);
		expect(mocks.toast.success).not.toHaveBeenCalled();
		expect(onDragBusyChange).toHaveBeenLastCalledWith(false);
	});
});
