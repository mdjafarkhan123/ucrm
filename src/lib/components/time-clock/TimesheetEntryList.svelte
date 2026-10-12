<script lang="ts">
	import { resolve } from '$app/paths';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import type { TimesheetEntryActions } from '$lib/time-clock/corrections';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { durationLabel } from '$lib/time-clock/api';
	import { clockTime, entryPurpose, type TimesheetEntry } from '$lib/time-clock/timesheets';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import playerStopIcon from '@tabler/icons/outline/player-stop.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// One person's entries, opened from their Timesheets row (plan § Timesheets page): what each was for,
	// notes, start, end and duration. The week groups them under their days; a day lists them as they are.
	// Times are the business's own clock, where the work happened.
	let {
		entries,
		userId,
		actions,
		days,
		timezone,
		grouped,
		offsetMs = 0,
		truncated = false
	}: {
		entries: TimesheetEntry[];
		/** Whose entries these are. */
		userId: string;
		/** Edit, stop, history and delete, opened by the page. */
		actions: TimesheetEntryActions;
		/** The window's days, so a week reads Sunday to Saturday with empty days left out. */
		days: string[];
		timezone: string;
		/** Group under day headings (the Week view). */
		grouped: boolean;
		/** How far the server's clock is ahead of this device's, for a running timer. */
		offsetMs?: number;
		truncated?: boolean;
	} = $props();

	const sections = $derived.by(() => {
		if (!grouped) return [{ day: null as string | null, entries, minutes: 0 }];
		return days
			.map((day) => {
				const onDay = entries.filter((entry) => entry.started_on === day);
				return {
					day: day as string | null,
					entries: onDay,
					minutes: onDay.reduce((sum, entry) => sum + (entry.minutes ?? 0), 0)
				};
			})
			.filter((section) => section.entries.length > 0);
	});

	// Edit, Stop, History and Delete, each only when the reader may (the database said so per entry).
	function menuItems(entry: TimesheetEntry) {
		const items = [];
		if (entry.can_edit) {
			items.push({
				label: entry.is_running ? 'Edit start or notes' : 'Edit',
				icon: pencilIcon,
				onSelect: () => actions.edit(entry, userId)
			});
		}
		if (entry.is_running && entry.can_edit) {
			items.push({
				label: entry.over_a_day ? 'Set end time' : 'Stop…',
				icon: playerStopIcon,
				onSelect: () => actions.stop(entry, userId)
			});
		}
		items.push({ label: 'History', icon: historyIcon, onSelect: () => actions.history(entry) });
		if (entry.can_delete) {
			items.push({
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				onSelect: () => actions.remove(entry, userId)
			});
		}
		return items;
	}

	function sourceLabel(entry: TimesheetEntry) {
		const made = entry.is_running ? 'Running' : entry.source === 'timer' ? 'Timer' : 'Typed';
		return entry.edited ? `${made} · Edited` : made;
	}

	function timeRange(entry: TimesheetEntry) {
		const start = clockTime(entry.started_at, timezone);
		if (!entry.ended_at) return `${start} – now`;
		return `${start} – ${clockTime(entry.ended_at, timezone)}`;
	}
</script>

<!-- The icon is a Tabler SVG file imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
{#if entries.length === 0}
	<p class="timesheet-entries__empty">No hours recorded.</p>
{:else}
	{#each sections as section (section.day ?? 'all')}
		<section class="timesheet-entries__day">
			{#if section.day}
				<h4 class="timesheet-entries__heading">
					<span
						>{formatCalendarDay(section.day, {
							weekday: 'long',
							month: 'short',
							day: 'numeric'
						})}</span
					>
					{#if section.minutes > 0}<span>{durationLabel(section.minutes)}</span>{/if}
				</h4>
			{/if}
			<ul class="timesheet-entries__list">
				{#each section.entries as entry (entry.id)}
					<li
						class="timesheet-entry"
						class:timesheet-entry--running={entry.is_running}
						class:timesheet-entry--flagged={entry.overlaps}
					>
						<span class="timesheet-entry__time">{timeRange(entry)}</span>
						<div class="timesheet-entry__what">
							{#if entry.job?.visible}
								<a
									class="timesheet-entry__job"
									href={resolve('/(app)/jobs/[id=uuid]', { id: entry.job.id })}
								>
									{entryPurpose(entry)}
								</a>
							{:else}
								<span class="timesheet-entry__purpose">{entryPurpose(entry)}</span>
							{/if}
							{#if entry.job?.client_name}
								<span class="timesheet-entry__client">{entry.job.client_name}</span>
							{/if}
							{#if entry.notes}<p class="timesheet-entry__notes">{entry.notes}</p>{/if}
							{#if entry.overlaps}
								<span class="timesheet-entry__warning">
									<span aria-hidden="true">{@html alertIcon}</span>
									Overlaps another entry
								</span>
							{/if}
						</div>
						<span class="timesheet-entry__source">{sourceLabel(entry)}</span>
						<span class="timesheet-entry__duration">
							{#if entry.is_running}
								<RunningClock startedAt={entry.started_at} {offsetMs} flagLong />
							{:else if entry.minutes !== null}
								{durationLabel(entry.minutes)}
							{/if}
						</span>
						<span
							class="timesheet-entry__menu"
							role="presentation"
							onpointerenter={() => actions.warm(entry)}
							onfocusin={() => actions.warm(entry)}
						>
							<DropdownMenu items={menuItems(entry)} triggerLabel="Entry actions" />
						</span>
					</li>
				{/each}
			</ul>
		</section>
	{/each}
	{#if truncated}
		<p class="timesheet-entries__empty">
			Only the first 400 entries are shown. Choose a single day to see the rest.
		</p>
	{/if}
{/if}

<style lang="scss">
	.timesheet-entries__empty {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.timesheet-entries__day + .timesheet-entries__day {
		margin-top: var(--space-base);
	}

	.timesheet-entries__heading {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		margin-bottom: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.timesheet-entries__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.timesheet-entry {
		display: grid;
		grid-template-columns: 11rem minmax(0, 1fr) 7rem 6rem 2rem;
		align-items: start;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
		font-size: var(--typography--fontSize-small);

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		&--flagged {
			box-shadow: inset 3px 0 0 var(--color-warning);
		}
	}

	.timesheet-entry__time {
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.timesheet-entry__what {
		display: flex;
		flex-direction: column;
		gap: var(--space-minuscule);
		min-width: 0;
	}

	.timesheet-entry__job {
		color: var(--color-interactive);
		font-weight: 600;
		text-decoration: none;
		overflow-wrap: anywhere;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			border-radius: var(--radius-small);
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.timesheet-entry__purpose {
		color: var(--color-text);
		font-weight: 600;
	}

	.timesheet-entry__client,
	.timesheet-entry__notes {
		color: var(--color-text--secondary);
		overflow-wrap: anywhere;
	}

	.timesheet-entry__notes {
		margin: 0;
		white-space: pre-line;
	}

	.timesheet-entry__warning {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		color: var(--color-warning--onSurface);
		font-weight: 600;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.timesheet-entry__source {
		color: var(--color-text--secondary);
	}

	.timesheet-entry__menu {
		display: flex;
		justify-content: flex-end;
		margin: calc(var(--space-smaller) * -1) 0;
	}

	.timesheet-entry__duration {
		justify-self: end;
		color: var(--color-text);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	@media (max-width: 639px) {
		.timesheet-entry {
			grid-template-columns: minmax(0, 1fr) auto auto;
			gap: var(--space-smaller) var(--space-base);
		}

		.timesheet-entry__time {
			grid-column: 1;
			grid-row: 1;
		}

		.timesheet-entry__duration {
			grid-column: 2;
			grid-row: 1;
		}

		.timesheet-entry__menu {
			grid-column: 3;
			grid-row: 1;
		}

		.timesheet-entry__what {
			grid-column: 1 / -1;
		}

		.timesheet-entry__source {
			grid-column: 1 / -1;
			font-size: var(--typography--fontSize-smaller);
		}
	}
</style>
