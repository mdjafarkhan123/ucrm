<script lang="ts">
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { filterBacklog, backlogAgeLabel } from '$lib/schedule/backlog';
	import {
		visitAssignmentLabel,
		visitClientLabel,
		visitPlaceLabel,
		visitWorkLabel
	} from '$lib/schedule/labels';
	import type { ScheduleEmployeeFilter } from '$lib/schedule/filters';
	import type { UnscheduledVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import gripIcon from '@tabler/icons/outline/grip-vertical.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';

	// The Unscheduled backlog: every visit with no date yet, waiting to be placed. It docks beside the
	// calendar rather than over it -- no backdrop -- so a card can be dragged straight out onto the grid
	// while both are visible. The drawer never writes: it hands each gesture back to the page, which invokes
	// the same Jobs-owned command the drag-move already uses.

	let {
		visits,
		loading = false,
		error = '',
		truncated = false,
		limit,
		today,
		employees,
		employeesById,
		canSchedule = false,
		query = $bindable(''),
		employee = $bindable('all'),
		dropZone = $bindable(null),
		placingVisitId = null,
		onClose,
		onRetry,
		onSchedule,
		onPreview,
		onPickUp
	}: {
		visits: UnscheduledVisit[];
		loading?: boolean;
		error?: string;
		truncated?: boolean;
		limit?: number;
		today: string;
		employees: TeamMember[];
		employeesById: Map<string, TeamMember>;
		/** Whether this reader may place work. Without it the drawer is read-only: no handle, no Schedule. */
		canSchedule?: boolean;
		/** The search box, kept by the page so it survives the drawer being closed and reopened. */
		query?: string;
		/** The assignment filter, kept by the page for the same reason. */
		employee?: ScheduleEmployeeFilter;
		/** The list element a calendar card is dropped onto to send a visit back to the backlog. */
		dropZone?: HTMLElement | null;
		/** A backlog visit currently being dragged onto the calendar, shown as lifted while it travels. */
		placingVisitId?: string | null;
		onClose: () => void;
		onRetry: () => void;
		/** The explicit Schedule action, and the keyboard path a drag has no equivalent for. */
		onSchedule: (visit: UnscheduledVisit) => void;
		onPreview: (visit: UnscheduledVisit, element: HTMLElement) => void;
		/** The drag handle was pressed. The page decides whether it becomes a drag onto the calendar. */
		onPickUp: (event: PointerEvent, visit: UnscheduledVisit) => void;
	} = $props();

	const shown = $derived(filterBacklog(visits, { query, employee }));

	const employeeOptions = $derived([
		{ value: 'all', label: 'All employees' },
		{ value: 'unassigned', label: 'Unassigned' },
		...employees.map((member) => ({
			value: member.id,
			label: member.full_name ?? 'Unnamed employee'
		}))
	]);

	// A filter is hiding work when the backlog has visits but the current search or employee shows none.
	const filteredEmpty = $derived(!loading && !error && visits.length > 0 && shown.length === 0);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<aside class="backlog" aria-label="Unscheduled work">
	<header class="backlog__head">
		<div class="backlog__title">
			<h2 class="backlog__heading">Unscheduled</h2>
			{#if !loading && !error}
				<span class="backlog__count">{visits.length}</span>
			{/if}
		</div>
		<button
			type="button"
			class="backlog__close"
			aria-label="Close unscheduled work"
			onclick={onClose}
		>
			{@html closeIcon}
		</button>
	</header>

	<div class="backlog__filters">
		<SearchInput
			id="backlog-search"
			bind:value={query}
			ariaLabel="Search unscheduled work"
			placeholder="Search client, work or place"
		/>
		<Select
			id="backlog-employee"
			bind:value={employee}
			ariaLabel="Filter unscheduled work by employee"
			options={employeeOptions}
		/>
	</div>

	<!-- The drop target for sending a calendar card back to the backlog. It is the scrollable list itself,
	     so a visit dropped anywhere in the drawer is unscheduled -- after the page's confirmation. -->
	<div class="backlog__list" bind:this={dropZone}>
		{#if loading}
			<LoadingSkeleton variant="card" rows={4} label="Loading unscheduled work" />
		{:else if error}
			<div class="backlog__state" role="alert">
				<p class="backlog__state-text">{error}</p>
				<Button size="small" variant="secondary" onclick={onRetry}>Try again</Button>
			</div>
		{:else if visits.length === 0}
			<div class="backlog__state">
				<span class="backlog__state-icon" aria-hidden="true">{@html inboxIcon}</span>
				<p class="backlog__state-text">Nothing is waiting to be scheduled.</p>
				<p class="backlog__state-hint">A new job you leave undated shows up here to place later.</p>
			</div>
		{:else if filteredEmpty}
			<div class="backlog__state">
				<p class="backlog__state-text">No unscheduled work matches your search.</p>
			</div>
		{:else}
			{#if truncated && limit}
				<p class="backlog__notice" role="status">
					Showing the first {limit}. Schedule or filter some to see the rest.
				</p>
			{/if}
			<ul class="backlog__items">
				{#each shown as visit (visit.id)}
					<li class="backlog__item" class:backlog__item--placing={placingVisitId === visit.id}>
						{#if canSchedule}
							<!-- The handle picks the card up. Dragging is pointer-only; the Schedule button below is
							     the keyboard path to the same placement. -->
							<span
								class="backlog__grip"
								aria-hidden="true"
								onpointerdown={(event) => onPickUp(event, visit)}
							>
								{@html gripIcon}
							</span>
						{/if}
						<button
							type="button"
							class="backlog__card"
							onclick={(event) => onPreview(visit, event.currentTarget)}
						>
							<span class="backlog__client">{visitClientLabel(visit)}</span>
							<span class="backlog__work">{visitWorkLabel(visit)}</span>
							{#if visitPlaceLabel(visit)}
								<span class="backlog__place">{visitPlaceLabel(visit)}</span>
							{/if}
							<span class="backlog__meta">
								<span
									class="backlog__assignment"
									class:backlog__assignment--none={visit.assignee_ids.length === 0}
								>
									{visitAssignmentLabel(visit, employeesById)}
								</span>
								<span class="backlog__age"
									>{backlogAgeLabel(visit.created_at.slice(0, 10), today)}</span
								>
							</span>
						</button>
						{#if canSchedule}
							<div class="backlog__actions">
								<Button size="small" variant="secondary" onclick={() => onSchedule(visit)}>
									Schedule
								</Button>
							</div>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</div>
</aside>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.backlog {
		display: flex;
		flex: 0 0 340px;
		flex-direction: column;
		width: 340px;
		max-height: clamp(360px, calc(100vh - 300px), 940px);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.backlog__head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.backlog__title {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.backlog__heading {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
	}

	.backlog__count {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 24px;
		height: 22px;
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-large);
		background-color: var(--color-surface--active);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
	}

	.backlog__close {
		display: grid;
		flex: 0 0 auto;
		width: 32px;
		height: 32px;
		place-items: center;
		margin: calc(var(--space-smaller) * -1);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.backlog__filters {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-small) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.backlog__list {
		flex: 1 1 auto;
		padding: var(--space-small) var(--space-base);
		overflow-y: auto;
	}

	.backlog__notice {
		margin: 0 0 var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
	}

	.backlog__items {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.backlog__item {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		align-items: start;
		gap: var(--space-smaller);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-left: var(--border-thick) solid var(--color-visit);
		border-radius: var(--radius-small);
		background-color: var(--color-surface);

		&--placing {
			opacity: 0.4;
		}
	}

	.backlog__grip {
		display: grid;
		place-items: center;
		width: 20px;
		height: 20px;
		color: var(--color-icon--secondary);
		cursor: grab;
		touch-action: none;

		&:active {
			cursor: grabbing;
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.backlog__card {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
		padding: 0;
		border: 0;
		background: transparent;
		color: var(--color-text);
		font-family: inherit;
		text-align: left;
		cursor: pointer;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
			border-radius: var(--radius-small);
		}
	}

	.backlog__client {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.backlog__work,
	.backlog__place {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.backlog__meta {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		margin-top: var(--space-smallest);
	}

	.backlog__assignment {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;

		&--none {
			color: var(--color-warning--onSurface);
			font-weight: 700;
		}
	}

	.backlog__age {
		flex-shrink: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.backlog__actions {
		grid-column: 2;
		display: flex;
		justify-content: flex-end;
	}

	.backlog__state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-large) var(--space-base);
		text-align: center;
	}

	.backlog__state-icon {
		display: grid;
		place-items: center;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 32px;
			height: 32px;
		}
	}

	.backlog__state-text {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.backlog__state-hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-base);
	}
</style>
