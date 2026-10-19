<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import {
		clientScheduleKey,
		fetchClientSchedule,
		type ClientReadError,
		type ClientScheduleEntry
	} from '$lib/clients/api';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import clipboardIcon from '@tabler/icons/outline/clipboard-list.svg?raw';

	// The client page's Client schedule: this client's visits and on-site assessments, the way Jobber's client
	// page shows "upcoming and past scheduled visits for this client". Upcoming is everything booked and not
	// yet done — anything overdue first — and Past is what has been done, latest first.
	//
	// Bookings are changed on the job, the request and the Schedule, never here, so this reads fresh every
	// time the client page opens (staleTime 0) while still painting the last answer straight away. A member
	// who may not see the schedule at all (no jobs.view) gets no section rather than an empty one.

	let {
		clientId,
		clientName,
		locale
	}: {
		clientId: string;
		/** The first name, for the line under the title. */
		clientName: string;
		locale?: string;
	} = $props();

	let view = $state<'upcoming' | 'past'>('upcoming');

	const scheduleQuery = createQuery(() => ({
		queryKey: clientScheduleKey(clientId),
		queryFn: () => fetchClientSchedule(clientId),
		staleTime: 0
	}));
	// Names for the Assigned column. The same cached team list the visit dialogs use.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 5 * 60 * 1000
	}));

	const denied = $derived((scheduleQuery.error as ClientReadError | null)?.status === 403);
	const schedule = $derived(scheduleQuery.data);
	const entries = $derived((view === 'upcoming' ? schedule?.upcoming : schedule?.past) ?? []);
	const hasMore = $derived(
		view === 'upcoming' ? schedule?.has_more_upcoming : schedule?.has_more_past
	);
	const memberNames = $derived(
		new Map((teamQuery.data ?? []).map((member) => [member.id, member.full_name]))
	);

	// A plain calendar day, read at noon UTC so it stays the same day in every browser timezone.
	const weekdayFormat = $derived(
		new Intl.DateTimeFormat(locale, { weekday: 'short', timeZone: 'UTC' })
	);
	const dayNumberFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', timeZone: 'UTC' })
	);
	const dayFormat = $derived(
		new Intl.DateTimeFormat(locale, {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
			timeZone: 'UTC'
		})
	);
	const dayYearFormat = $derived(
		new Intl.DateTimeFormat(locale, {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
			year: 'numeric',
			timeZone: 'UTC'
		})
	);
	const clockFormat = $derived(
		new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' })
	);
	// An assessment's time is an instant, so it is read on the contractor's own clock, not the browser's.
	const instantClockFormat = $derived(
		new Intl.DateTimeFormat(locale, {
			hour: 'numeric',
			minute: '2-digit',
			timeZone: schedule?.timezone
		})
	);

	const noon = (value: string) => new Date(`${value}T12:00:00Z`);

	function formatDay(value: string) {
		if (value === schedule?.today) return 'Today';
		const sameYear = value.slice(0, 4) === schedule?.today.slice(0, 4);
		return (sameYear ? dayFormat : dayYearFormat).format(noon(value));
	}
	function formatClock(value: string) {
		return clockFormat.format(new Date(`2000-01-01T${value}`));
	}

	function whenLabel(entry: ClientScheduleEntry) {
		if (!entry.date) return 'No date yet';
		const day = formatDay(entry.date);
		if (entry.start_time) {
			const start = formatClock(entry.start_time);
			return entry.end_time
				? `${day} · ${start} – ${formatClock(entry.end_time)}`
				: `${day} · ${start}`;
		}
		if (entry.starts_at) {
			const start = instantClockFormat.format(new Date(entry.starts_at));
			return entry.ends_at
				? `${day} · ${start} – ${instantClockFormat.format(new Date(entry.ends_at))}`
				: `${day} · ${start}`;
		}
		return `${day} · Anytime`;
	}

	// Who is on it, as the avatars the schedule uses elsewhere. A teammate the list does not know yet still
	// counts, as a plain "+1", rather than vanishing.
	function crewOf(entry: ClientScheduleEntry) {
		const known = entry.assignee_ids
			.filter((id) => memberNames.has(id))
			.map((id) => ({ id, name: memberNames.get(id) ?? '' }));
		return { known, unknown: entry.assignee_ids.length - known.length };
	}

	function recordHref(entry: ClientScheduleEntry) {
		if (entry.kind === 'visit') return resolve('/(app)/jobs/[id=uuid]', { id: entry.record_id });
		return resolve('/(app)/requests/[id=uuid]', { id: entry.record_id });
	}
</script>

{#if !denied}
	<SectionBlock
		tone="client"
		title="Client schedule"
		subtitle={`Visits and assessments booked for ${clientName}`}
		icon={calendarIcon}
		level={2}
		class="section-block--flush client-schedule"
	>
		{#snippet actions()}
			<SegmentedControl
				size="small"
				bind:value={view}
				options={[
					{ value: 'upcoming', label: 'Upcoming' },
					{ value: 'past', label: 'Past' }
				]}
			/>
		{/snippet}

		{#if scheduleQuery.isPending}
			<div class="client-schedule__pad">
				<LoadingSkeleton variant="table" label="Loading this client's schedule" rows={3} />
			</div>
		{:else if scheduleQuery.isError}
			<div class="client-schedule__pad">
				<ErrorState
					description="This client's schedule could not be loaded. Refresh and try again."
				/>
			</div>
		{:else if entries.length === 0}
			<div class="client-schedule__pad">
				<EmptyState
					icon={calendarIcon}
					title={view === 'upcoming' ? 'Nothing booked' : 'Nothing done yet'}
					description={view === 'upcoming'
						? 'Visits and assessments booked for this client will show up here.'
						: 'Visits and assessments completed for this client will show up here.'}
				/>
			</div>
		{:else}
			<ul
				class="client-schedule__list"
				aria-label={view === 'upcoming' ? 'Upcoming for this client' : 'Past for this client'}
			>
				{#each entries as entry, index (`${entry.kind}:${entry.id}`)}
					{@const crew = crewOf(entry)}
					{@const next = view === 'upcoming' && index === 0 && !entry.overdue}
					<li class="client-schedule__row" class:client-schedule__row--next={next}>
						<span class="client-schedule__tile" class:client-schedule__tile--next={next}>
							{#if entry.date}
								<span class="client-schedule__weekday"
									>{weekdayFormat.format(noon(entry.date))}</span
								>
								<span class="client-schedule__day">{dayNumberFormat.format(noon(entry.date))}</span>
							{:else}
								<span class="client-schedule__day">—</span>
							{/if}
						</span>

						<div class="client-schedule__info">
							<div class="client-schedule__heading">
								<a class="client-schedule__link" href={recordHref(entry)}>{entry.title}</a>
								{#if entry.overdue}
									<Badge size="small" status="warning">Overdue</Badge>
								{/if}
							</div>
							<span class="client-schedule__when">{whenLabel(entry)}</span>
							<span class="client-schedule__record">
								<span class="client-schedule__record-icon" aria-hidden="true"
									>{@html entry.kind === 'visit' ? hammerIcon : clipboardIcon}</span
								>
								{entry.record_label}
							</span>
						</div>

						<div class="client-schedule__crew">
							{#if entry.assignee_ids.length === 0}
								<span class="client-schedule__unassigned">Unassigned</span>
							{:else}
								<ul class="client-schedule__avatars" aria-label="Assigned">
									{#each crew.known as member (member.id)}
										<li title={member.name}>
											<Avatar id={member.id} name={member.name} size="base" />
										</li>
									{/each}
									{#if crew.unknown > 0}
										<li class="client-schedule__more-people">+{crew.unknown}</li>
									{/if}
								</ul>
							{/if}
						</div>
					</li>
				{/each}
			</ul>
			{#if hasMore}
				<p class="client-schedule__more">
					{view === 'upcoming'
						? 'Showing the next ones only. Open a job to see all of its visits.'
						: 'Showing the latest ones only. Open a job to see all of its visits.'}
				</p>
			{/if}
		{/if}
	</SectionBlock>
{/if}

<style lang="scss">
	.client-schedule {
		&__pad {
			padding: 0 24px 24px;
		}

		&__list {
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: 16px;
			padding: 16px 24px;
			border-top: var(--border-base) solid var(--color-border);

			// The next thing on the calendar stands out; everything after it is quieter.
			&--next {
				background: var(--color-surface--background--subtle);
			}
		}

		&__tile {
			display: flex;
			flex: 0 0 52px;
			width: 52px;
			height: 56px;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: 1px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);

			&--next {
				border-color: var(--color-interactive);
				color: var(--color-text--reverse);
				background: var(--color-interactive);
			}
		}

		&__weekday {
			font-size: 10px;
			font-weight: 700;
			letter-spacing: 0.6px;
			text-transform: uppercase;
			opacity: 0.8;
		}

		&__day {
			font-size: 20px;
			font-variant-numeric: tabular-nums;
			font-weight: 700;
			line-height: 1.1;
		}

		&__info {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 4px;
		}

		&__heading {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}

		&__link {
			overflow: hidden;
			color: var(--color-heading);
			font-size: 15px;
			font-weight: 600;
			text-decoration: none;
			text-overflow: ellipsis;
			white-space: nowrap;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__when {
			color: var(--color-text--secondary);
			font-size: 13px;
			font-weight: 500;
		}

		&__record {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: 12px;
			font-weight: 500;
		}

		&__record-icon {
			display: inline-flex;

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}

		&__crew {
			display: flex;
			flex: 0 0 auto;
			justify-content: flex-end;
		}

		&__unassigned {
			color: var(--color-text--secondary);
			font-size: 13px;
		}

		&__avatars {
			display: flex;
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				margin-left: -6px;
				border: 2px solid var(--color-surface);
				border-radius: 50%;
				background: var(--color-surface);
			}
			li:first-child {
				margin-left: 0;
			}
		}

		&__more-people {
			display: inline-grid;
			width: 32px;
			height: 32px;
			place-items: center;
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle) !important;
			font-size: 11px;
			font-weight: 700;
		}

		&__more {
			margin: 0;
			padding: 12px 24px;
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: center;
		}
	}

	@media (max-width: 599px) {
		.client-schedule__row {
			flex-wrap: wrap;
		}
		.client-schedule__crew {
			margin-left: 68px;
		}
	}
</style>
