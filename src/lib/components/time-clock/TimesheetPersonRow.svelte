<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import TimesheetEntryList from '$lib/components/time-clock/TimesheetEntryList.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import type { TimesheetEntryActions } from '$lib/time-clock/corrections';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { durationLabel } from '$lib/time-clock/api';
	import {
		fetchTimesheetEntries,
		personName,
		runningPurpose,
		timesheetEntriesKey,
		type TimesheetPerson,
		type TimesheetSpan
	} from '$lib/time-clock/timesheets';
	import chevronIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// One person on the Timesheets page (plan § Timesheets page): their total for each day and for the window,
	// and, once opened, each entry. Two table rows: the person, then their entries spanning the whole table, the
	// way an expandable data-table row works (Carbon, Primer). The name is the disclosure button; a click
	// anywhere else on the row does the same for a mouse. Entries are their own read, made when the row is
	// opened or first pointed at, so the page's size follows the team, not the hours.
	let {
		person,
		span,
		days,
		from,
		to,
		timezone,
		offsetMs,
		open,
		teamView,
		menu = [],
		entryActions,
		ontoggle
	}: {
		person: TimesheetPerson;
		span: TimesheetSpan;
		/** The window's days: one in Day, Sunday to Saturday in Week. */
		days: string[];
		from: string;
		to: string;
		timezone: string;
		/** How far the server's clock is ahead of this device's, for a running timer. */
		offsetMs: number;
		open: boolean;
		/** The reader sees the whole team, so their own row is marked "You". */
		teamView: boolean;
		/** What the reader may do for this person: add hours, clock them in, clock them out. */
		menu?: { label: string; icon?: string; onSelect: () => void }[];
		/** Edit, stop, history and delete on each entry. Without them the entries are read-only. */
		entryActions?: TimesheetEntryActions;
		ontoggle: () => void;
	} = $props();

	let warm = $state(false);

	const entriesQuery = createQuery(() => ({
		queryKey: timesheetEntriesKey(person.user_id, from, to),
		queryFn: () => fetchTimesheetEntries(person.user_id, from, to),
		enabled: open || warm,
		staleTime: 30_000
	}));

	const panelId = $derived(`timesheet-entries-${person.user_id}`);
	const name = $derived(personName(person));
	const statusBadge = $derived(
		person.status === 'removed'
			? 'Left the team'
			: person.status === 'deactivated'
				? 'Deactivated'
				: person.status === 'pending'
					? 'Invited'
					: null
	);
	// Every stopped entry in this window is approved (plan § Weekly approval).
	const approved = $derived(person.entry_count > 0 && person.unapproved_count === 0);
	const runningFor = $derived(person.running ? runningPurpose(person.running) : null);

	// A click on the row's empty space opens it too. Its own controls, and a drag to select text, keep
	// their meaning.
	function rowClick(event: MouseEvent) {
		if ((event.target as Element).closest('button, a')) return;
		if (window.getSelection()?.toString()) return;
		ontoggle();
	}

	function entryCountLabel(count: number) {
		if (count === 0) return 'No hours';
		return count === 1 ? '1 entry' : `${count} entries`;
	}
</script>

<!-- The icon is a Tabler SVG file imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<tr
	class="timesheet-person timesheet-person--{span}"
	class:timesheet-person--open={open}
	onclick={rowClick}
	onpointerenter={() => (warm = true)}
>
	<th scope="row" class="timesheet-person__who">
		<div class="timesheet-person__line">
			<button
				type="button"
				class="timesheet-person__toggle"
				aria-expanded={open}
				aria-controls={panelId}
				onclick={ontoggle}
				onfocus={() => (warm = true)}
			>
				<span class="timesheet-person__chevron" aria-hidden="true">{@html chevronIcon}</span>
				<Avatar id={person.user_id} name={person.name} src={person.avatar_url} size="small" />
				<span class="timesheet-person__name">{name}</span>
			</button>
			{#if menu.length > 0}
				<DropdownMenu items={menu} triggerLabel={`Actions for ${name}`} />
			{/if}
		</div>
		{#if (teamView && person.is_me) || statusBadge || approved || person.overlap_count > 0 || person.running}
			<span class="timesheet-person__marks">
				{#if teamView && person.is_me}<Badge size="small">You</Badge>{/if}
				{#if statusBadge}<Badge size="small" status="inactive" dot={false}>{statusBadge}</Badge
					>{/if}
				{#if approved}<Badge size="small" status="success" dot={false}>Approved</Badge>{/if}
				{#if person.overlap_count > 0}
					<Badge size="small" status="warning" dot={false}>
						{person.overlap_count === 1 ? '1 overlap' : `${person.overlap_count} overlaps`}
					</Badge>
				{/if}
				{#if person.running}
					<span class="timesheet-person__running">
						<RunningClock startedAt={person.running.started_at} {offsetMs} flagLong />
						<span class="timesheet-person__running-for">{runningFor}</span>
					</span>
				{/if}
			</span>
		{/if}
	</th>

	{#if span === 'week'}
		{#each days as day (day)}
			{@const minutes = person.days[day] ?? 0}
			<td class="timesheet-person__day">
				<span class="timesheet-person__day-name"
					>{formatCalendarDay(day, { weekday: 'short' })}</span
				>
				{#if minutes > 0}
					{durationLabel(minutes)}
				{:else}
					<span class="timesheet-person__none"
						><span aria-hidden="true">–</span><span class="timesheet-person__sr">No hours</span
						></span
					>
				{/if}
			</td>
		{/each}
	{:else}
		<td class="timesheet-person__count">{entryCountLabel(person.entry_count)}</td>
	{/if}

	<td
		class="timesheet-person__total"
		class:timesheet-person__total--none={person.total_minutes === 0}
	>
		{person.total_minutes > 0 ? durationLabel(person.total_minutes) : '0h'}
	</td>
</tr>

{#if open}
	<tr class="timesheet-person__panel">
		<td id={panelId} colspan={span === 'week' ? days.length + 2 : 3}>
			{#if entriesQuery.isPending}
				<p class="timesheet-person__status" role="status">Loading {name}'s hours…</p>
			{:else if entriesQuery.isError}
				<p class="timesheet-person__status timesheet-person__status--error" role="alert">
					{entriesQuery.error.message}
					<Button
						variant="quiet"
						size="small"
						loading={entriesQuery.isFetching}
						onclick={() => void entriesQuery.refetch()}
					>
						Try again
					</Button>
				</p>
			{:else}
				<TimesheetEntryList
					entries={entriesQuery.data.entries}
					userId={person.user_id}
					actions={entryActions}
					{days}
					{timezone}
					grouped={span === 'week'}
					{offsetMs}
					truncated={entriesQuery.data.truncated}
				/>
			{/if}
		</td>
	</tr>
{/if}

<style lang="scss">
	.timesheet-person {
		cursor: pointer;
		transition: background-color var(--timing-quick) ease;

		&:hover,
		&--open {
			background-color: var(--color-surface--background--subtle);
		}

		th,
		td {
			padding: var(--space-base) var(--space-small);
			border-bottom: var(--border-base) solid var(--color-border);
			vertical-align: middle;
		}

		th {
			padding-left: var(--space-base);
		}

		td:last-child {
			padding-right: var(--space-large);
		}

		&--open th,
		&--open td {
			border-bottom-color: transparent;
		}
	}

	.timesheet-person__who {
		min-width: 15rem;
		text-align: left;
		font-weight: 400;
	}

	.timesheet-person__line {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		/* The menu's 32px button must not make the row taller than the name. */
		margin: calc(var(--space-smaller) * -1) 0;
	}

	.timesheet-person__toggle {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		max-width: 100%;
		padding: var(--space-smallest) var(--space-smaller) var(--space-smallest) 0;
		border: 0;
		border-radius: var(--radius-small);
		background: transparent;
		color: var(--color-heading);
		font: inherit;
		font-weight: 600;
		text-align: left;
		cursor: pointer;

		&:hover .timesheet-person__name {
			color: var(--color-interactive);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.timesheet-person__chevron {
		display: inline-flex;
		flex: none;
		color: var(--color-text--secondary);
		transition: transform var(--timing-base) ease;

		:global(svg) {
			width: 16px;
			height: 16px;
		}

		.timesheet-person--open & {
			transform: rotate(180deg);
		}
	}

	.timesheet-person__name {
		min-width: 0;
		overflow-wrap: anywhere;
		transition: color var(--timing-quick) ease;
	}

	.timesheet-person__marks {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-smaller);
		margin-top: var(--space-smaller);
		padding-left: calc(16px + var(--space-small));
	}

	.timesheet-person__running {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
	}

	.timesheet-person__running-for {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.timesheet-person__day,
	.timesheet-person__total,
	.timesheet-person__count {
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		text-align: right;
		white-space: nowrap;
	}

	.timesheet-person__day-name {
		display: none;
	}

	.timesheet-person__none {
		color: var(--color-text--secondary);
	}

	.timesheet-person__sr {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}

	.timesheet-person__count {
		color: var(--color-text--secondary);
	}

	.timesheet-person__total {
		color: var(--color-heading);
		font-weight: 700;

		&--none {
			color: var(--color-text--secondary);
			font-weight: 400;
		}
	}

	.timesheet-person__panel td {
		padding: 0 var(--space-large) var(--space-large)
			calc(var(--space-base) + 16px + var(--space-small));
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface--background--subtle);
	}

	.timesheet-person__status {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			color: var(--color-critical--onSurface);
		}
	}

	/* A phone has no room for nine columns: the name and total share the top line and the week's days drop
	   beneath them as a strip, each with its own day name, since the column headings are hidden. */
	@media (max-width: 639px) {
		.timesheet-person {
			display: grid;
			grid-template-columns: repeat(7, minmax(0, 1fr));
			align-items: center;
			border-bottom: var(--border-base) solid var(--color-border);

			th,
			td {
				padding: 0;
				border-bottom: 0;
			}

			&--open {
				border-bottom-color: transparent;
			}
		}

		.timesheet-person--week {
			row-gap: var(--space-small);
			padding: var(--space-base);
		}

		.timesheet-person--day {
			grid-template-columns: minmax(0, 1fr) auto;
			column-gap: var(--space-base);
			padding: var(--space-base);
		}

		.timesheet-person__who {
			grid-row: 1;
			grid-column: 1 / 6;
			min-width: 0;

			.timesheet-person--day & {
				grid-column: 1;
			}
		}

		.timesheet-person__total {
			grid-row: 1;
			grid-column: 6 / 8;
			align-self: start;
			padding: var(--space-smallest) 0 0 !important;

			.timesheet-person--day & {
				grid-column: 2;
			}
		}

		.timesheet-person__count {
			grid-row: 2;
			grid-column: 1;
			padding-left: calc(16px + var(--space-small)) !important;
			text-align: left;
			font-size: var(--typography--fontSize-small);
		}

		.timesheet-person__day {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-minuscule);
			padding: var(--space-smaller) 0;
			border-radius: var(--radius-small);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
			align-self: start;
			text-align: center;
			/* A seventh of a phone is too narrow for "6h 29m": the minutes go under the hours. */
			white-space: normal;
		}

		.timesheet-person__day-name {
			display: block;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		/* Under the avatar, in line with the entry count below. */
		.timesheet-person__marks {
			padding-left: calc(16px + var(--space-small));
		}

		.timesheet-person__panel {
			display: block;

			td {
				display: block;
				padding: 0 var(--space-base) var(--space-base);
			}
		}
	}
</style>
