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
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import zoomCancelIcon from '@tabler/icons/outline/zoom-cancel.svg?raw';
	import cloudOffIcon from '@tabler/icons/outline/cloud-off.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import infoCircleIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import { initials } from '$lib/collaboration/format';

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
		ownScheduleOnly = false,
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
		/** This reader only sees their own work, so an employee filter here has nobody else to offer. */
		ownScheduleOnly?: boolean;
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

	/** The names of whoever a backlog visit is for, in order, for the little initials beside the label. */
	function peopleOf(visit: UnscheduledVisit) {
		return visit.assignee_ids
			.slice(0, 3)
			.map((id) => employeesById.get(id)?.full_name ?? 'One employee');
	}

	// A filter is hiding work when the backlog has visits but the current search or employee shows none.
	const filteredEmpty = $derived(!loading && !error && visits.length > 0 && shown.length === 0);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<aside class="backlog" aria-label="Unscheduled work">
	<header class="backlog__head">
		<div class="backlog__title">
			<span class="backlog__tile" aria-hidden="true">{@html inboxIcon}</span>
			<h2 class="backlog__heading">Unscheduled</h2>
			{#if !loading && !error}
				<span class="backlog__count">{visits.length}</span>
			{/if}
		</div>
		<Button
			variant="secondary"
			size="small"
			iconOnly
			label="Close unscheduled work"
			onclick={onClose}
		>
			{@html closeIcon}
		</Button>
	</header>

	<div class="backlog__filters">
		<SearchInput
			id="backlog-search"
			bind:value={query}
			ariaLabel="Search unscheduled work"
			placeholder="Search client, work or place"
		/>
		{#if !ownScheduleOnly}
			<Select
				id="backlog-employee"
				bind:value={employee}
				ariaLabel="Filter unscheduled work by employee"
				options={employeeOptions}
				icon={usersIcon}
				class="backlog__select"
			/>
		{/if}
	</div>

	<!-- The drop target for sending a calendar card back to the backlog. It is the scrollable list itself,
	     so a visit dropped anywhere in the drawer is unscheduled -- after the page's confirmation. -->
	<div class="backlog__list" bind:this={dropZone}>
		{#if loading}
			<LoadingSkeleton variant="card" rows={4} label="Loading unscheduled work" />
		{:else if error}
			<div class="backlog__state" role="alert">
				<span class="backlog__state-icon backlog__state-icon--critical" aria-hidden="true">
					{@html cloudOffIcon}
				</span>
				<p class="backlog__state-text">{error}</p>
				<div class="backlog__retry">
					<Button variant="secondary" onclick={onRetry}>
						{@html refreshIcon}
						Try again
					</Button>
				</div>
			</div>
		{:else if visits.length === 0}
			<div class="backlog__state">
				<span class="backlog__state-icon" aria-hidden="true">{@html inboxIcon}</span>
				<p class="backlog__state-text">Nothing is waiting to be scheduled.</p>
				<p class="backlog__state-hint">A new job you leave undated shows up here to place later.</p>
			</div>
		{:else if filteredEmpty}
			<div class="backlog__state">
				<span class="backlog__state-icon" aria-hidden="true">{@html zoomCancelIcon}</span>
				<p class="backlog__state-text">No unscheduled work matches your search.</p>
			</div>
		{:else}
			{#if truncated && limit}
				<p class="backlog__notice" role="status">
					<span class="backlog__notice-icon" aria-hidden="true">{@html infoCircleIcon}</span>
					Showing the first {limit}. Schedule or filter some to see the rest.
				</p>
			{/if}
			<ul class="backlog__items">
				{#each shown as visit (visit.id)}
					{@const people = peopleOf(visit)}
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
						<div class="backlog__body">
							<button
								type="button"
								class="backlog__card"
								onclick={(event) => onPreview(visit, event.currentTarget)}
							>
								<span class="backlog__top">
									<span class="backlog__client">{visitClientLabel(visit)}</span>
									<span class="backlog__age">
										<span class="backlog__age-icon" aria-hidden="true">{@html clockIcon}</span>
										{backlogAgeLabel(visit.created_at.slice(0, 10), today)}
									</span>
								</span>
								<span class="backlog__work">{visitWorkLabel(visit)}</span>
								{#if visitPlaceLabel(visit)}
									<span class="backlog__place">
										<span class="backlog__place-icon" aria-hidden="true">{@html mapPinIcon}</span>
										<span class="backlog__place-text">{visitPlaceLabel(visit)}</span>
									</span>
								{/if}
							</button>
							<div class="backlog__foot">
								{#if visit.assignee_ids.length === 0}
									<span class="backlog__unassigned">
										<span class="backlog__unassigned-dot" aria-hidden="true"></span>
										Unassigned
									</span>
								{:else}
									<span class="backlog__people">
										<span class="backlog__avatars" aria-hidden="true">
											{#each people as person, index (index)}
												<span class="backlog__avatar">{initials(person)}</span>
											{/each}
										</span>
										<span class="backlog__assignment">
											{visitAssignmentLabel(visit, employeesById)}
										</span>
									</span>
								{/if}
								{#if canSchedule}
									<Button variant="secondary" size="small" onclick={() => onSchedule(visit)}>
										{@html calendarIcon}
										Schedule
									</Button>
								{/if}
							</div>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</div>
</aside>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The backlog is a card of its own beside the calendar's, as tall as the calendar, with the list scrolling
	// inside it.
	.backlog {
		display: flex;
		flex: 0 0 340px;
		flex-direction: column;
		width: 340px;
		min-height: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	@media (max-width: 767px) {
		.backlog {
			flex: 0 0 auto;
			width: 100%;
			max-height: 80dvh;
		}
	}

	.backlog__head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-base) 20px 0;
	}

	.backlog__title {
		display: flex;
		align-items: center;
		gap: 10px;
		min-width: 0;
	}

	.backlog__tile {
		display: grid;
		flex: 0 0 auto;
		width: 36px;
		height: 36px;
		place-items: center;
		border-radius: 10px;
		background-color: var(--color-warning--surface);
		color: var(--color-warning--onSurface);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.backlog__heading {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		letter-spacing: -0.2px;
		line-height: var(--typography--lineHeight-tight);
	}

	.backlog__count {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 22px;
		height: 20px;
		padding: 0 7px;
		border-radius: 999px;
		background-color: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: 11px;
		font-weight: 700;
	}

	.backlog__filters {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 10px;
		padding: var(--space-base) 20px;
		border-bottom: var(--border-base) solid var(--color-border);

		> :global(*) {
			align-self: stretch;
		}

		> :global(.backlog__select) {
			align-self: flex-start;
			width: auto;
		}
	}

	.backlog__list {
		flex: 1 1 auto;
		min-height: 0;
		padding: var(--space-base) 20px 20px;
		overflow-y: auto;
	}

	.backlog__notice {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		margin: 0 0 var(--space-small);
		padding: 10px 12px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		font-size: 12px;
		line-height: 1.4;
	}

	.backlog__notice-icon {
		display: inline-flex;
		flex-shrink: 0;
		margin-top: 1px;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.backlog__items {
		display: flex;
		flex-direction: column;
		gap: 12px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	// The whole card is a drop-shaped unit: a grip strip down the left to pick it up by, and the work to
	// the right of it.
	.backlog__item {
		display: flex;
		align-items: stretch;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
		transition: box-shadow var(--timing-quick) ease;

		&:hover {
			box-shadow: var(--shadow-base);
		}

		&--placing {
			opacity: 0.4;
		}
	}

	.backlog__grip {
		display: grid;
		flex: 0 0 20px;
		place-items: center;
		border-right: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface--background--subtle);
		color: var(--color-icon--secondary);
		cursor: grab;
		touch-action: none;

		&:active {
			cursor: grabbing;
		}

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.backlog__body {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: 10px;
		min-width: 0;
		padding: 12px 14px;
	}

	.backlog__card {
		display: flex;
		flex-direction: column;
		gap: 4px;
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

	.backlog__top {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-small);
		min-width: 0;
	}

	.backlog__client {
		min-width: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		line-height: 1.3;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.backlog__age {
		display: inline-flex;
		flex-shrink: 0;
		align-items: center;
		gap: 4px;
		color: var(--color-text--secondary);
		font-size: 11.5px;
		white-space: nowrap;
	}

	.backlog__age-icon,
	.backlog__place-icon {
		display: inline-flex;
		flex-shrink: 0;

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.backlog__work {
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		line-height: 1.4;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.backlog__place {
		display: flex;
		align-items: center;
		gap: 5px;
		min-width: 0;
		color: var(--color-text--secondary);
		font-size: 12px;
	}

	.backlog__place-text {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.backlog__foot {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding-top: 10px;
		border-top: var(--border-base) solid var(--color-border);
	}

	.backlog__people {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.backlog__avatars {
		display: inline-flex;
	}

	.backlog__avatar {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 22px;
		border: 2px solid var(--color-surface);
		border-radius: 999px;
		background-color: var(--color-surface--background--subtle);
		color: var(--color-text--secondary);
		font-size: 8.5px;
		font-weight: 700;

		& + & {
			margin-left: -6px;
		}
	}

	.backlog__assignment {
		color: var(--color-text--secondary);
		font-size: 12px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	// Nobody is on it yet. A pill, not just a word, because this is the thing a dispatcher is hunting for.
	.backlog__unassigned {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 4px 9px 4px 8px;
		border-radius: 999px;
		background-color: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: 11.5px;
		font-weight: 600;
	}

	.backlog__unassigned-dot {
		width: 6px;
		height: 6px;
		border-radius: var(--radius-circle);
		background-color: var(--color-warning);
	}

	.backlog__state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-small);
		padding: 64px var(--space-base) var(--space-large);
		text-align: center;
	}

	.backlog__state-icon {
		display: grid;
		width: 48px;
		height: 48px;
		margin-bottom: var(--space-smaller);
		place-items: center;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 22px;
			height: 22px;
		}
	}

	.backlog__state-icon--critical {
		border-color: transparent;
		background-color: var(--color-critical--surface);
		color: var(--color-critical);
	}

	.backlog__state-text {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
	}

	.backlog__state-hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.backlog__retry {
		margin-top: var(--space-smaller);
	}
</style>
