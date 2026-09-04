<script lang="ts">
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
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import mapIcon from '@tabler/icons/outline/map-2.svg?raw';

	let {
		filters,
		rangeLabel,
		employees,
		employeesFailed = false,
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

	const viewOptions = SCHEDULE_VIEWS.map((view) => ({
		value: view,
		label: SCHEDULE_VIEW_LABELS[view]
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
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="schedule-controls">
	<div class="schedule-controls__date">
		<div class="schedule-controls__stepper">
			<button
				type="button"
				class="schedule-controls__step"
				aria-label="Previous {filters.view}"
				onclick={() => onstep(-1)}
			>
				{@html chevronLeftIcon}
			</button>
			<button
				type="button"
				class="schedule-controls__step"
				aria-label="Next {filters.view}"
				onclick={() => onstep(1)}
			>
				{@html chevronRightIcon}
			</button>
		</div>

		<Button variant="secondary" size="small" onclick={ontoday}>Today</Button>

		<p class="schedule-controls__range" aria-live="polite">{rangeLabel}</p>
	</div>

	<div class="schedule-controls__filters">
		<SegmentedControl
			value={filters.view}
			options={viewOptions}
			size="small"
			label="View"
			onchange={(view) => onchange({ view: view as ScheduleFilters['view'] })}
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

		<div class="schedule-controls__field">
			<Select
				id="schedule-employee"
				label="Employee"
				value={filters.employee}
				options={employeeOptions}
				disabled={employeesFailed}
				onchange={(employee) => onchange({ employee })}
			/>
		</div>

		<div class="schedule-controls__field">
			<Select
				id="schedule-status"
				label="Status"
				value={filters.status}
				options={statusOptions}
				onchange={(status) => onchange({ status: status as ScheduleFilters['status'] })}
			/>
		</div>

		{#if onunscheduled}
			<button
				type="button"
				class="schedule-controls__unscheduled"
				class:schedule-controls__unscheduled--active={unscheduledOpen}
				aria-pressed={unscheduledOpen}
				onclick={onunscheduled}
				onpointerenter={onunscheduledhover}
				onfocus={onunscheduledhover}
			>
				Unscheduled
				{#if unscheduledCount !== null}
					<span class="schedule-controls__badge">{unscheduledCount}</span>
				{/if}
			</button>
		{/if}

		{#if onmap}
			<button
				type="button"
				class="schedule-controls__unscheduled schedule-controls__map"
				class:schedule-controls__unscheduled--active={mapOpen}
				aria-pressed={mapOpen}
				onclick={onmap}
			>
				{@html mapIcon}
				Map
			</button>
		{/if}
	</div>
</div>

<style lang="scss">
	.schedule-controls {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.schedule-controls__date {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.schedule-controls__stepper {
		display: flex;
		gap: var(--space-smaller);
	}

	.schedule-controls__unscheduled {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		height: 34px;
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		color: var(--color-text);
		font-family: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;
		transition: background-color var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--active {
			border-color: var(--color-interactive);
			background-color: var(--color-surface--active);
		}
	}

	.schedule-controls__map {
		gap: var(--space-smaller);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.schedule-controls__badge {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 20px;
		height: 18px;
		padding: 0 var(--space-smallest);
		border-radius: var(--radius-large);
		background-color: var(--color-interactive);
		color: var(--color-surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
	}

	.schedule-controls__step {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 32px;
		height: 32px;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		color: var(--color-icon);
		cursor: pointer;
		transition: background-color var(--timing-quick) ease;

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

	.schedule-controls__range {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		line-height: var(--typography--lineHeight-large);
	}

	.schedule-controls__filters {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-slim);
	}

	// A Select is `width: 100%`, so without a width of its own each one takes whatever the row will give it
	// and the three controls wrap onto three lines on an ordinary desktop. 200px is the width every other
	// filter in the app uses, in `FilterField`.
	.schedule-controls__field {
		width: 200px;
	}

	@media (max-width: 767px) {
		.schedule-controls__field {
			width: 100%;
		}
	}
</style>
