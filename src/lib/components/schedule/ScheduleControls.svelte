<script lang="ts">
	import { Popover } from 'bits-ui';
	import CalendarBar from '$lib/components/calendar/CalendarBar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import {
		SCHEDULE_VIEWS,
		SCHEDULE_VIEW_LABELS,
		VISIT_DERIVED_STATUSES,
		VISIT_STATUS_LABELS
	} from '$lib/schedule/statuses';
	import type { ScheduleFilters } from '$lib/schedule/filters';
	import { SCHEDULE_ZOOMS, SCHEDULE_ZOOM_LABELS, type ScheduleZoom } from '$lib/schedule/density';
	import type { TeamMember } from '$lib/team/api';
	import mapIcon from '@tabler/icons/outline/map-2.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import inboxIcon from '@tabler/icons/outline/calendar-off.svg?raw';
	import monthIcon from '@tabler/icons/outline/calendar-month.svg?raw';
	import weekIcon from '@tabler/icons/outline/calendar-week.svg?raw';
	import dayIcon from '@tabler/icons/outline/calendar.svg?raw';

	let {
		filters,
		rangeLabel,
		employees,
		employeesFailed = false,
		ownScheduleOnly = false,
		zoom,
		showZoom = false,
		unscheduledCount = null,
		unscheduledOpen = false,
		mapOpen = false,
		onstep,
		ontoday,
		onchange,
		onzoom,
		onunscheduled,
		onunscheduledhover,
		onmap
	}: {
		filters: ScheduleFilters;
		/** The window in words, e.g. "Aug 30 – Sep 5, 2026". The page owns the wording. */
		rangeLabel: string;
		employees: TeamMember[];
		/** The team could not be loaded, so the Employee filter cannot honestly offer names. */
		employeesFailed?: boolean;
		/**
		 * This reader only ever sees their own work, so there is no Employee filter to offer: every choice in
		 * it but their own name returns nothing. Jobber does the same -- field crew get their own schedule and
		 * no team picker at all.
		 */
		ownScheduleOnly?: boolean;
		/** The reader's grid zoom. A viewing preference, kept apart from the data filters. */
		zoom: ScheduleZoom;
		/** Only the time-based views (Week, Day) have an hour axis to zoom; Month hides the control. */
		showZoom?: boolean;
		/** How many visits wait in the backlog. Null until the count has been read. */
		unscheduledCount?: number | null;
		/** Whether the Unscheduled drawer is open, so the toggle reads pressed. */
		unscheduledOpen?: boolean;
		/** Whether the Map workspace is open, so the toggle reads pressed. */
		mapOpen?: boolean;
		/** Move one whole window back or forward. */
		onstep: (direction: -1 | 1) => void;
		ontoday: () => void;
		onchange: (next: Partial<ScheduleFilters>) => void;
		onzoom: (zoom: ScheduleZoom) => void;
		/** Open or close the Unscheduled drawer. Absent when there is no drawer to toggle. */
		onunscheduled?: () => void;
		/** The toggle was hovered or focused, a cue to warm the backlog read before it is opened. */
		onunscheduledhover?: () => void;
		/** Open or close the Map workspace. */
		onmap?: () => void;
	} = $props();

	const viewIcons = { month: monthIcon, week: weekIcon, day: dayIcon };
	const viewOptions = [...SCHEDULE_VIEWS].reverse().map((view) => ({
		value: view,
		label: SCHEDULE_VIEW_LABELS[view],
		icon: viewIcons[view],
		iconColor: 'var(--color-time)'
	}));

	const statusOptions = [
		{ value: 'all', label: 'All statuses' },
		...VISIT_DERIVED_STATUSES.map((status) => ({
			value: status,
			label: VISIT_STATUS_LABELS[status]
		}))
	];

	const zoomOptions = SCHEDULE_ZOOMS.map((value) => ({
		value,
		label: SCHEDULE_ZOOM_LABELS[value]
	}));

	const employeeOptions = $derived([
		{ value: 'all', label: 'All employees' },
		{ value: 'unassigned', label: 'Unassigned' },
		...employees.map((member) => ({
			value: member.id,
			label: member.full_name ?? 'Unnamed employee'
		}))
	]);

	// The row was getting long, so the data filters live behind a single "Filters" button (the pattern Jobber
	// uses). The badge counts only filters that are actually narrowing the list -- Employee and Status. Density
	// rides along in the panel because it belongs with the other view options, but it is a viewing preference,
	// not a filter, so it never lights the badge.
	let filtersOpen = $state(false);

	const activeFilterCount = $derived(
		(!ownScheduleOnly && filters.employee !== 'all' ? 1 : 0) + (filters.status !== 'all' ? 1 : 0)
	);

	function clearFilters() {
		onchange({ employee: 'all', status: 'all' });
	}
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<CalendarBar
	view={filters.view}
	views={viewOptions}
	{rangeLabel}
	{onstep}
	{ontoday}
	onview={(view) => onchange({ view })}
>
	{#snippet extras()}
		<span class="schedule-controls__divider" aria-hidden="true"></span>
		{#if onunscheduled}
			<Button
				variant="secondary"
				pressed={unscheduledOpen}
				count={unscheduledCount}
				onclick={onunscheduled}
				onhover={onunscheduledhover}
			>
				{@html inboxIcon}
				Unscheduled
			</Button>
		{/if}

		<div class="schedule-controls__joined">
			{#if onmap}
				<Button variant="secondary" pressed={mapOpen} onclick={onmap}>
					{@html mapIcon}
					Map
				</Button>
			{/if}

			<Popover.Root bind:open={filtersOpen}>
				<Popover.Trigger>
					{#snippet child({ props })}
						<Button
							{...props}
							variant="secondary"
							pressed={filtersOpen || activeFilterCount > 0}
							count={activeFilterCount > 0 ? activeFilterCount : null}
							label={activeFilterCount > 0 ? `Filters, ${activeFilterCount} active` : undefined}
						>
							{@html filterIcon}
							Filters
						</Button>
					{/snippet}
				</Popover.Trigger>
				<Popover.Portal>
					<Popover.Content
						class="schedule-controls__filters-panel"
						align="end"
						sideOffset={8}
						collisionPadding={16}
					>
						<header class="schedule-controls__filters-header">
							<h2>Filters</h2>
							{#if activeFilterCount > 0}
								<Button variant="quiet" size="small" onclick={clearFilters}>Clear</Button>
							{/if}
						</header>

						<div class="schedule-controls__filters-body">
							{#if !ownScheduleOnly}
								<Select
									id="schedule-employee"
									label="Employee"
									value={filters.employee}
									options={employeeOptions}
									disabled={employeesFailed}
									contentClass="schedule-controls__filters-select"
									onchange={(employee) => onchange({ employee })}
								/>
							{/if}

							<Select
								id="schedule-status"
								label="Status"
								value={filters.status}
								options={statusOptions}
								contentClass="schedule-controls__filters-select"
								onchange={(status) => onchange({ status: status as ScheduleFilters['status'] })}
							/>

							{#if showZoom}
								<SegmentedControl
									value={zoom}
									options={zoomOptions}
									size="small"
									label="Density"
									onchange={(value) => onzoom(value as ScheduleZoom)}
								/>
							{/if}
						</div>
					</Popover.Content>
				</Popover.Portal>
			</Popover.Root>
		</div>
	{/snippet}
</CalendarBar>

<style lang="scss">
	.schedule-controls__divider {
		width: 1px;
		height: 24px;
		background: var(--color-border);
		margin: 0 var(--space-smaller);
	}
	.schedule-controls__joined {
		display: inline-flex;
		:global(.button) {
			border-radius: 0;
		}
		:global(.button:first-child) {
			border-radius: var(--radius-base) 0 0 var(--radius-base);
		}
		:global(.button:last-child) {
			border-radius: 0 var(--radius-base) var(--radius-base) 0;
		}
		:global(.button:only-child) {
			border-radius: var(--radius-base);
		}
		:global(.button + .button) {
			margin-left: -1px;
		}
		:global(.button:focus-visible) {
			z-index: 1;
		}
	}

	/* The floating Filters panel, on the design skill's popover tokens (surface, base border, --shadow-base,
	   --elevation-tooltip). A Select inside is width:100%, so it fills the column on its own. */
	:global(.schedule-controls__filters-panel) {
		z-index: var(--elevation-tooltip);
		display: flex;
		flex-direction: column;
		width: min(320px, calc(100vw - var(--space-large) * 2));
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background-color: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	/* The Employee/Status Selects float their options at --elevation-modal, one layer below this popover's
	   --elevation-tooltip -- fine when a Select sits directly on the page, but here it is nested inside the
	   panel, so its options must outrank the panel that hosts them or they render underneath it. */
	:global(.schedule-controls__filters-select) {
		z-index: calc(var(--elevation-tooltip) + 1);
	}

	.schedule-controls__filters-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);

		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
	}

	.schedule-controls__filters-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-base);
	}
</style>
