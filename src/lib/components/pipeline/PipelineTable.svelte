<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import StageAgeChip from './StageAgeChip.svelte';
	import TaskDialog from './TaskDialog.svelte';
	import {
		boardTableKey,
		bulkUpdateOpportunities,
		fetchBoardColumn,
		fetchMentionableTeammates,
		invalidatePipeline,
		mentionableTeammatesKey,
		type BulkChange,
		type TaskInput,
		type BoardColumnPage,
		type OpportunityCard as Card
	} from '$lib/pipeline/api';
	import { BULK_CARD_LIMIT, cardCount, summarizeBulk } from '$lib/pipeline/bulk';
	import {
		BOARD_SORTS,
		boardFilterKey,
		sortHasDirection,
		type BoardFilters,
		type BoardSort
	} from '$lib/pipeline/filters';
	import { inactivity, stageAge, type InactivityRules } from '$lib/pipeline/freshness';
	import { followUp, formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import {
		ALL_STAGE_LABELS,
		TABLE_SCOPE,
		isAnyBoardStage,
		type CustomStage
	} from '$lib/pipeline/stages';

	// The board's cards as one list (Pipedrive's list view, HubSpot's table view): the same search, filters
	// and order, read through the same route, one row per card. Read only — a row opens the same Brief a
	// card does, and moving work stays with the Brief and the board. The one thing the table adds is bulk
	// work: tick several rows to change their owner, give each a Task, or place them in a custom stage —
	// nothing that talks to a customer, converts, closes, or moves a protected stage (plan § First-release
	// board).
	let {
		filters,
		formatting,
		canViewValue,
		canEdit = false,
		customStages = [],
		inactivityRules = null,
		onOpen,
		onSortChange
	}: {
		filters: BoardFilters;
		// Null until the board summary has answered; money and dates wait for it.
		formatting: BoardFormatting | null;
		// The Value column is absent, not empty, for a member who may not see money.
		canViewValue: boolean;
		// Whether this member may change cards, which decides if rows can be ticked at all.
		canEdit?: boolean;
		customStages?: readonly CustomStage[];
		inactivityRules?: InactivityRules | null;
		onOpen: (card: Card) => void;
		onSortChange: (sort: BoardSort) => void;
	} = $props();

	const query = createInfiniteQuery(() => ({
		queryKey: boardTableKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchBoardColumn(TABLE_SCOPE, filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: BoardColumnPage) => page.next_cursor ?? undefined,
		// The same window as the columns, so switching views inside it never re-fetches either one.
		staleTime: 30_000
	}));

	const rows = $derived(query.data?.pages.flatMap((page) => page.opportunities) ?? []);

	// A new search, filter, or order is a new list, so whatever was ticked in the old one is let go rather
	// than acted on out of sight.
	let selectedIds = $derived.by(() => {
		boardFilterKey(filters);
		return new Set<string>();
	});
	const tooMany = $derived(selectedIds.size > BULK_CARD_LIMIT);

	const queryClient = useQueryClient();
	const toast = getToastManager();
	let working = $state(false);
	let taskOpen = $state(false);

	// The Salesperson filter has already loaded this list, so the owner menu opens on it warm.
	const teamQuery = createQuery(() => ({
		queryKey: mentionableTeammatesKey,
		queryFn: fetchMentionableTeammates,
		staleTime: 300_000,
		enabled: canEdit
	}));

	// Runs one bulk change over the ticked cards and says what happened in one toast. Cards that were refused
	// stay ticked, so the next step — say, adding the follow-up Task an on-hold stage asked for — is one click.
	async function applyBulk(change: BulkChange, doneLabel: string) {
		const ids = [...selectedIds];
		working = true;
		try {
			const summary = summarizeBulk(await bulkUpdateOpportunities(ids, change));
			void invalidatePipeline(queryClient);
			selectedIds = new Set(summary.refusedIds);
			const changed = summary.done + summary.unchanged;
			if (summary.refusedIds.length === 0) {
				toast.success(`${cardCount(changed)} ${doneLabel}`);
			} else {
				const why = summary.reasons
					.map(({ reason, count }) => `${cardCount(count)}: ${reason}`)
					.join(' ');
				toast.warning(
					changed > 0
						? `${cardCount(changed)} ${doneLabel}, ${summary.refusedIds.length} not changed`
						: `${summary.refusedIds.length === 1 ? 'That card was' : 'Those cards were'} not changed`,
					`${why} The ones not changed are still ticked.`
				);
			}
		} finally {
			working = false;
		}
	}

	async function bulkOwner(ownerId: string | null, name: string) {
		try {
			await applyBulk({ action: 'owner', owner_user_id: ownerId }, `given to ${name}`);
		} catch (thrown) {
			toast.error('Could not change the owner', (thrown as Error).message);
		}
	}
	async function bulkPlace(stageId: string, name: string) {
		try {
			await applyBulk({ action: 'place', custom_stage_id: stageId }, `moved to ${name}`);
		} catch (thrown) {
			toast.error('Could not move the cards', (thrown as Error).message);
		}
	}
	// A refusal of the whole request throws back into the dialog, which shows it under the form.
	async function bulkTask(task: TaskInput) {
		await applyBulk({ action: 'task', task }, 'given the task');
		taskOpen = false;
	}

	const ownerItems = $derived([
		{ label: 'Unassigned', onSelect: () => void bulkOwner(null, 'nobody') },
		...(teamQuery.data ?? []).map((member) => {
			const name = member.full_name ?? 'Unnamed teammate';
			return { label: name, onSelect: () => void bulkOwner(member.id, name) };
		})
	]);
	// Requests and Quotes each have their own follow-up stages, and a card only fits its own section's, so
	// the menu keeps them apart rather than offering one list that half the cards will refuse.
	const stageGroups = $derived(
		(['request', 'quote'] as const)
			.map((section) => ({
				heading: section === 'request' ? 'Requests' : 'Quotes',
				items: customStages
					.filter((stage) => stage.section === section)
					.map((stage) => ({
						label: stage.name,
						note: stage.requires_future_task ? 'Needs a future task' : undefined,
						onSelect: () => void bulkPlace(stage.id, stage.name)
					}))
			}))
			.filter((group) => group.items.length > 0)
	);

	// A header sorts only when it is one of the board's own orders; every other column reads in that order.
	const columns = $derived<DataTableColumn[]>([
		{ key: 'title', label: 'Opportunity' },
		{ key: 'stage', label: 'Stage' },
		{ key: 'owner', label: 'Salesperson' },
		{ key: 'attention', label: 'Next Task', sortable: true },
		{ key: 'time_in_stage', label: 'Time in stage', sortable: true },
		...(canViewValue
			? [{ key: 'value', label: 'Value', align: 'end' as const, sortable: true }]
			: []),
		{ key: 'close', label: 'Expected close', sortable: true },
		{ key: 'created', label: 'Created', sortable: true },
		{ key: 'source', label: 'Lead source' }
	]);

	// "Time in stage" is the `stage` order; the header key cannot be `stage`, which is the Stage column.
	const headerFor = (sort: BoardSort) => (sort === 'stage' ? 'time_in_stage' : sort);
	const sortFor = (header: string): BoardSort | null => {
		const sort = header === 'time_in_stage' ? 'stage' : header;
		return (BOARD_SORTS as readonly string[]).includes(sort) ? (sort as BoardSort) : null;
	};
	// The Task order has no direction, so its header shows it as the order in use without an arrow pointing
	// either way it could be read as reversing.
	const sort = $derived<DataTableSort>({
		key: headerFor(filters.sort),
		direction: sortHasDirection(filters.sort) && filters.direction === 'desc' ? 'desc' : 'asc'
	});

	function changeSort(header: string) {
		const next = sortFor(header);
		if (next) onSortChange(next);
	}

	function stageName(card: Card) {
		const custom = card.custom_stage_id
			? customStages.find((stage) => stage.id === card.custom_stage_id)
			: undefined;
		return (
			custom?.name ?? (isAnyBoardStage(card.stage) ? ALL_STAGE_LABELS[card.stage] : card.stage)
		);
	}
	// A card in a custom stage is still really a Draft or a New request underneath, the same thing the card's
	// badge says on the board.
	function realStage(card: Card) {
		return card.custom_stage_id && isAnyBoardStage(card.stage)
			? ALL_STAGE_LABELS[card.stage]
			: null;
	}
	function clientName(card: Card) {
		return card.client?.company_name?.trim() || card.client?.display_name || 'No client';
	}
	function day(value: string | null, plain: boolean) {
		if (!value || !formatting) return null;
		// A plain date has no zone and is read as one; an instant is read in the organization's calendar.
		if (plain) return followUp(value, formatting)?.label ?? null;
		return new Date(value).toLocaleDateString(formatting.locale, {
			timeZone: formatting.timezone,
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}
</script>

{#if query.isPending}
	<LoadingSkeleton variant="table" rows={8} />
{:else if query.isError}
	<ErrorState
		title="The table could not be loaded"
		description="Something went wrong on our side. Try again."
		retry={() => query.refetch()}
	/>
{:else if rows.length === 0}
	<EmptyState
		title="No cards match"
		description="Change the search or the filters to see more of the pipeline."
	/>
{:else}
	{#if canEdit && selectedIds.size > 0}
		<div class="pipeline-table__bulk" role="region" aria-label="Change the ticked cards">
			<span class="pipeline-table__bulk-count">{selectedIds.size} selected</span>
			{#if tooMany}
				<span class="pipeline-table__bulk-note">
					Tick {BULK_CARD_LIMIT} or fewer to change them together.
				</span>
			{:else}
				<DropdownMenu
					items={ownerItems}
					align="start"
					disabled={working}
					triggerClass="pipeline-table__bulk-trigger"
					triggerLabel={`Change the owner of ${cardCount(selectedIds.size)}`}
				>
					{#snippet trigger()}Change owner{/snippet}
				</DropdownMenu>
				<Button
					variant="secondary"
					size="small"
					disabled={working}
					onclick={() => (taskOpen = true)}>Add task</Button
				>
				{#if stageGroups.length > 0}
					<DropdownMenu
						groups={stageGroups}
						align="start"
						disabled={working}
						triggerClass="pipeline-table__bulk-trigger"
						triggerLabel={`Move ${cardCount(selectedIds.size)} to a follow-up stage`}
					>
						{#snippet trigger()}Move to stage{/snippet}
					</DropdownMenu>
				{/if}
			{/if}
			<Button
				variant="tertiary"
				variation="subtle"
				size="small"
				class="pipeline-table__bulk-clear"
				disabled={working}
				onclick={() => (selectedIds = new Set())}>Clear</Button
			>
		</div>
	{/if}
	<DataTable
		{columns}
		items={rows}
		rowId={(card) => card.id}
		selectable={canEdit}
		bind:selectedIds
		rowLabel={(card) => `Select ${card.title}`}
		caption="Pipeline"
		onRowActivate={onOpen}
		{sort}
		onSortChange={changeSort}
	>
		{#snippet row(card: Card)}
			{@const task =
				formatting && card.task?.due_on ? followUp(card.task.due_on, formatting) : null}
			{@const age = stageAge(card.stage_entered_at)}
			{@const quiet = inactivity(card, inactivityRules)}
			{@const amount = formatting ? formatMoney(card.estimated_value, formatting) : null}
			<th scope="row">
				<!-- The keyboard's way in: the row click is a mouse convenience on top of this button. -->
				<button type="button" class="pipeline-table__open" onclick={() => onOpen(card)}>
					{card.title}
				</button>
				<span class="pipeline-table__sub">{clientName(card)}</span>
			</th>
			<td>
				<span class="pipeline-table__stage">{stageName(card)}</span>
				{#if realStage(card)}
					<span class="pipeline-table__sub">{realStage(card)}</span>
				{/if}
			</td>
			<td>
				{#if card.owner}
					<span class="pipeline-table__owner">
						<Avatar
							id={card.owner.id}
							name={card.owner.full_name}
							src={card.owner.avatar_url}
							size="small"
						/>
						{card.owner.full_name ?? 'Former teammate'}
					</span>
				{:else}
					Unassigned
				{/if}
			</td>
			<td>
				{#if card.task}
					<span class="pipeline-table__task">{card.task.title}</span>
					{#if task}
						<span
							class="pipeline-table__sub"
							class:pipeline-table__sub--overdue={task.overdue}
							title={task.description}>{task.overdue ? 'Overdue · ' : ''}{task.label}</span
						>
					{/if}
				{:else}
					<span class="pipeline-table__none">No Task</span>
				{/if}
			</td>
			<td>
				<span class="pipeline-table__age">
					<StageAgeChip label={age.label} description={age.description} />
					{#if quiet}
						<Badge size="small" status="warning">{quiet.label}</Badge>
					{/if}
				</span>
			</td>
			{#if canViewValue}
				<td class="align-end pipeline-table__number">{amount ?? '—'}</td>
			{/if}
			<td class="pipeline-table__number">{day(card.expected_close_on, true) ?? '—'}</td>
			<td class="pipeline-table__number">{day(card.created_at, false) ?? '—'}</td>
			<td>
				{#if card.client?.lead_source}
					<Badge size="small">{card.client.lead_source}</Badge>
				{:else}
					—
				{/if}
			</td>
		{/snippet}
		{#snippet footer()}
			<ListLoadMore
				hasNextPage={query.hasNextPage}
				isFetchingNextPage={query.isFetchingNextPage}
				onLoadMore={() => query.fetchNextPage()}
				endLabel="That is every card."
			/>
		{/snippet}
	</DataTable>
{/if}

{#if taskOpen}
	<TaskDialog
		open
		submit={bulkTask}
		bulkCount={selectedIds.size}
		timezone={formatting?.timezone}
		onClose={() => (taskOpen = false)}
	/>
{/if}

<style lang="scss">
	.pipeline-table__bulk {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.pipeline-table__bulk-count {
		margin-right: var(--space-small);
		color: var(--color-heading);
		font-weight: 600;
	}
	.pipeline-table__bulk-note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.pipeline-table__bulk :global(.pipeline-table__bulk-clear) {
		margin-left: auto;
	}
	.pipeline-table__bulk :global(.pipeline-table__bulk-trigger) {
		display: inline-flex;
		align-items: center;
		min-height: 36px;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			cursor: not-allowed;
			opacity: 0.6;
		}
	}
	.pipeline-table__open {
		display: block;
		padding: 0;
		border: 0;
		background: none;
		color: var(--color-heading);
		font: inherit;
		font-weight: 700;
		text-align: start;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive);
			text-decoration: underline;
		}
		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}
	.pipeline-table__sub {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.pipeline-table__sub--overdue {
		color: var(--color-critical);
		font-weight: 600;
	}
	.pipeline-table__stage,
	.pipeline-table__task {
		display: block;
		color: var(--color-text);
		white-space: nowrap;
	}
	.pipeline-table__owner,
	.pipeline-table__age {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		white-space: nowrap;
	}
	.pipeline-table__none {
		color: var(--color-text--secondary);
	}
	.pipeline-table__number {
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
</style>
