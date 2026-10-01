import { page } from 'vitest/browser';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import PipelineColumn from './PipelineColumn.svelte';
import { DEFAULT_BOARD_FILTERS } from '$lib/pipeline/filters';
import { DragWriteError, NEEDS_FUTURE_TASK, type OpportunityCard } from '$lib/pipeline/api';
import type { AnyBoardStage, BoardColumn, CustomStage } from '$lib/pipeline/stages';

const mocks = vi.hoisted(() => ({
	dragOpportunity: vi.fn(),
	placeOpportunity: vi.fn(),
	undoOpportunityMove: vi.fn(),
	undoOpportunityPlacement: vi.fn(),
	invalidatePipeline: vi.fn(),
	toast: {
		loading: vi.fn(() => 41),
		dismiss: vi.fn(),
		success: vi.fn(),
		error: vi.fn(),
		info: vi.fn(),
		show: vi.fn()
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
	// The Task dialog's team list, when an on-hold stage asks for a follow-up task.
	createQuery: () => ({ data: [] }),
	// The card's owner control, drawn once a column has a real card in it.
	createMutation: () => ({ mutate: vi.fn(), isPending: false }),
	useQueryClient: () => ({})
}));

vi.mock('$lib/components/ui/ToastManager.svelte', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/components/ui/ToastManager.svelte')>()),
	getToastManager: () => mocks.toast
}));

vi.mock('$lib/pipeline/api', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/pipeline/api')>()),
	dragOpportunity: mocks.dragOpportunity,
	placeOpportunity: mocks.placeOpportunity,
	undoOpportunityMove: mocks.undoOpportunityMove,
	undoOpportunityPlacement: mocks.undoOpportunityPlacement,
	invalidatePipeline: mocks.invalidatePipeline
}));

const card: OpportunityCard = {
	id: 'opportunity-1',
	title: 'Kitchen remodel',
	stage: 'assessment_unscheduled',
	custom_stage_id: null,
	stage_entered_at: '2026-08-23T00:00:00.000Z',
	progress_at: '2026-08-23T00:00:00.000Z',
	outcome: 'open',
	created_at: '2026-08-23T00:00:00.000Z',
	request: { id: 'request-1', status: 'assessment_unscheduled' },
	quote: null,
	client: null,
	property: null,
	owner: null,
	expected_close_on: null,
	task: null,
	assessment: null
};

const waitingOnCustomer: CustomStage = {
	id: '7b0c8f2e-0000-4000-8000-000000000001',
	section: 'request',
	name: 'Waiting on customer',
	after_stage: 'new_request',
	requires_future_task: false,
	inactivity_days: 2
};
const quoteFollowUp: CustomStage = {
	id: '7b0c8f2e-0000-4000-8000-000000000002',
	section: 'quote',
	name: 'Chasing a decision',
	after_stage: 'quote_awaiting_response',
	requires_future_task: false,
	inactivity_days: 2
};

function renderColumn(stage: AnyBoardStage | BoardColumn) {
	const onDragBusyChange = vi.fn();
	const screen = render(PipelineColumn, {
		props: {
			column: typeof stage === 'string' ? { kind: 'protected', key: stage } : stage,
			count: 0,
			valueTotal: null,
			filters: DEFAULT_BOARD_FILTERS,
			formatting: null,
			canEdit: true,
			onOpen: vi.fn(),
			customStages: [waitingOnCustomer, quoteFollowUp],
			dragging: { stage: card.stage, customStageId: null },
			onDraggingChange: vi.fn(),
			dragBusy: false,
			onDragBusyChange
		}
	});
	const zone = screen.container.querySelector('.pipeline-column__cards');
	if (!zone) throw new Error('Drop zone did not render.');
	return { screen, zone, onDragBusyChange };
}

function finalize(zone: Element, dropped: OpportunityCard = card) {
	zone.dispatchEvent(
		new CustomEvent('finalize', {
			detail: {
				items: [dropped],
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

	it('places a card dropped on a custom stage of its own section, with no dialog', async () => {
		mocks.placeOpportunity.mockResolvedValue({});
		const { zone, onDragBusyChange } = renderColumn({ kind: 'custom', stage: waitingOnCustomer });

		finalize(zone);

		await expect.element(page.getByRole('heading', { name: 'Waiting on customer' })).toBeVisible();
		await vi.waitFor(() =>
			expect(mocks.toast.success).toHaveBeenCalledWith('Moved to Waiting on customer.')
		);
		expect(mocks.placeOpportunity).toHaveBeenCalledWith(card.id, waitingOnCustomer.id);
		expect(mocks.dragOpportunity).not.toHaveBeenCalled();
		expect(mocks.invalidatePipeline).toHaveBeenCalledOnce();
		expect(onDragBusyChange).toHaveBeenLastCalledWith(false);
	});

	it('refuses a request card dropped on a Quotes stage, and says why, without asking the server', async () => {
		const { zone } = renderColumn({ kind: 'custom', stage: quoteFollowUp });

		finalize(zone);

		await vi.waitFor(() =>
			expect(mocks.toast.error).toHaveBeenCalledWith(
				'That card cannot go into Chasing a decision.',
				'This is a request, so it can only go into a Requests stage. Convert it to a quote first.'
			)
		);
		expect(mocks.placeOpportunity).not.toHaveBeenCalled();
		expect(mocks.toast.loading).not.toHaveBeenCalled();
	});

	it('puts a placed card back when it is dropped on its own real stage, with no domain action', async () => {
		mocks.placeOpportunity.mockResolvedValue({});
		const { zone } = renderColumn('assessment_unscheduled');

		finalize(zone, { ...card, custom_stage_id: waitingOnCustomer.id });

		await vi.waitFor(() =>
			expect(mocks.toast.success).toHaveBeenCalledWith('Moved to Assessment unscheduled.')
		);
		expect(mocks.placeOpportunity).toHaveBeenCalledWith(card.id, null);
		expect(mocks.dragOpportunity).not.toHaveBeenCalled();
	});

	it('runs the real action when a placed card is dropped on a later protected stage', async () => {
		const { zone } = renderColumn('assessment_completed');

		finalize(zone, { ...card, custom_stage_id: waitingOnCustomer.id });

		await vi.waitFor(() =>
			expect(mocks.toast.success).toHaveBeenCalledWith('Moved to Assessment completed.', undefined)
		);
		expect(mocks.dragOpportunity).toHaveBeenCalledWith(card.id, {
			toStage: 'assessment_completed',
			startsAt: undefined,
			endsAt: undefined
		});
		expect(mocks.placeOpportunity).not.toHaveBeenCalled();
	});

	it("reports the server's own reason when a placement is refused", async () => {
		mocks.placeOpportunity.mockRejectedValue(
			new Error('That stage is no longer on the board. Refresh the page and try again.')
		);
		const { zone } = renderColumn({ kind: 'custom', stage: waitingOnCustomer });

		finalize(zone);

		await vi.waitFor(() =>
			expect(mocks.toast.error).toHaveBeenCalledWith(
				'That card could not be moved.',
				'That stage is no longer on the board. Refresh the page and try again.'
			)
		);
		expect(mocks.invalidatePipeline).toHaveBeenCalledOnce();
	});

	it('offers the follow-up task when an on-hold stage refuses a card that has none', async () => {
		const message = 'Cards in “Waiting on customer” need a follow-up task with a future due date.';
		mocks.placeOpportunity.mockRejectedValue(
			new DragWriteError(message, { form: message }, NEEDS_FUTURE_TASK)
		);
		const { zone, onDragBusyChange } = renderColumn({
			kind: 'custom',
			stage: { ...waitingOnCustomer, requires_future_task: true }
		});

		finalize(zone);

		await expect.element(page.getByRole('dialog', { name: 'Add a follow-up task' })).toBeVisible();
		await expect
			.element(page.getByRole('button', { name: 'Add task and move card' }))
			.toBeDisabled();
		expect(mocks.toast.error).not.toHaveBeenCalled();
		// The board stays locked behind the dialog until the task is saved or the dialog is cancelled.
		expect(onDragBusyChange).toHaveBeenLastCalledWith(true);

		await page.getByRole('button', { name: 'Cancel' }).click();
		expect(onDragBusyChange).toHaveBeenLastCalledWith(false);
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
		await vi.waitFor(() =>
			expect(mocks.toast.success).toHaveBeenCalledWith('Moved to Assessment completed.', undefined)
		);
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

describe('PipelineColumn Move menu', () => {
	const newRequest: OpportunityCard = {
		...card,
		stage: 'new_request',
		request: { id: 'request-1', status: 'new' }
	};

	beforeEach(() => {
		vi.clearAllMocks();
		mocks.invalidatePipeline.mockResolvedValue(undefined);
		mocks.query.data = { pages: [{ opportunities: [newRequest] as never[], next_cursor: null }] };
		return () => {
			mocks.query.data = { pages: [{ opportunities: [], next_cursor: null }] };
		};
	});

	async function choose(destination: string | RegExp) {
		await page.getByRole('button', { name: 'Move Kitchen remodel' }).click();
		await page.getByRole('menuitem', { name: destination }).click();
	}

	it('moves the card without dragging, and its Undo takes exactly that move back', async () => {
		const moved = {
			id: card.id,
			from_stage: 'new_request',
			to_stage: 'assessment_unscheduled',
			undo: { restore_new_request: true }
		};
		mocks.dragOpportunity.mockResolvedValue(moved);
		mocks.undoOpportunityMove.mockResolvedValue({
			id: card.id,
			stage: 'new_request',
			custom_stage_id: null
		});
		renderColumn('new_request');

		await choose('Assessment unscheduled');

		await vi.waitFor(() =>
			expect(mocks.toast.show).toHaveBeenCalledWith(
				expect.objectContaining({
					title: 'Moved to Assessment unscheduled.',
					action: expect.objectContaining({ label: 'Undo' })
				})
			)
		);
		expect(mocks.dragOpportunity).toHaveBeenCalledWith(card.id, {
			toStage: 'assessment_unscheduled',
			startsAt: undefined,
			endsAt: undefined
		});

		mocks.toast.show.mock.calls[0][0].action.onSelect();

		await vi.waitFor(() =>
			expect(mocks.toast.success).toHaveBeenCalledWith('Moved back to New requests.')
		);
		expect(mocks.undoOpportunityMove).toHaveBeenCalledWith(card.id, moved);
	});

	it('opens the schedule dialog for Assessment scheduled, and saves nothing until it is confirmed', async () => {
		const { onDragBusyChange } = renderColumn('new_request');

		await choose('Assessment scheduled');

		await expect.element(page.getByText('Schedule the assessment - Kitchen remodel')).toBeVisible();
		expect(mocks.dragOpportunity).not.toHaveBeenCalled();
		expect(onDragBusyChange).toHaveBeenCalledWith(true);
	});

	it('says exactly why a blocked destination is blocked, without asking the server', async () => {
		renderColumn('new_request');

		await choose(/Assessment completed/);

		expect(mocks.toast.show).toHaveBeenCalledWith(
			expect.objectContaining({
				variant: 'warning',
				title: 'This card can’t move to Assessment completed.',
				message: expect.stringContaining('no assessment to complete yet')
			})
		);
		expect(mocks.dragOpportunity).not.toHaveBeenCalled();
		expect(mocks.toast.loading).not.toHaveBeenCalled();
	});

	it('places the card in a custom stage, and its Undo puts it back where it was', async () => {
		mocks.placeOpportunity.mockResolvedValue({ applied: true });
		mocks.undoOpportunityPlacement.mockResolvedValue({
			id: card.id,
			stage: 'new_request',
			custom_stage_id: null
		});
		renderColumn('new_request');

		await choose('Waiting on customer');

		await vi.waitFor(() =>
			expect(mocks.toast.show).toHaveBeenCalledWith(
				expect.objectContaining({ title: 'Moved to Waiting on customer.' })
			)
		);
		expect(mocks.placeOpportunity).toHaveBeenCalledWith(card.id, waitingOnCustomer.id);

		mocks.toast.show.mock.calls[0][0].action.onSelect();

		await vi.waitFor(() =>
			expect(mocks.toast.success).toHaveBeenCalledWith('Moved back to New requests.')
		);
		expect(mocks.undoOpportunityPlacement).toHaveBeenCalledWith(card.id, waitingOnCustomer.id);
		expect(mocks.placeOpportunity).toHaveBeenCalledTimes(1);
	});
});
