<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
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

	// The client page's Client schedule: this client's visits and on-site assessments, the way Jobber's client
	// page shows "upcoming and past scheduled visits for this client". Upcoming is everything booked and not
	// yet done — anything overdue first — and Past is what has been done, latest first.
	//
	// Bookings are changed on the job, the request and the Schedule, never here, so this reads fresh every
	// time the client page opens (staleTime 0) while still painting the last answer straight away. A member
	// who may not see the schedule at all (no jobs.view) gets no section rather than an empty one.

	let { clientId, locale }: { clientId: string; locale?: string } = $props();

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
	const dayFormat = $derived(
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

	function formatDay(value: string) {
		return dayFormat.format(new Date(`${value}T12:00:00Z`));
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
				? `${day} · ${start}–${formatClock(entry.end_time)}`
				: `${day} · ${start}`;
		}
		if (entry.starts_at) {
			const start = instantClockFormat.format(new Date(entry.starts_at));
			return entry.ends_at
				? `${day} · ${start}–${instantClockFormat.format(new Date(entry.ends_at))}`
				: `${day} · ${start}`;
		}
		return `${day} · Anytime`;
	}

	function assignedLabel(entry: ClientScheduleEntry) {
		if (entry.assignee_ids.length === 0) return 'Unassigned';
		const names = entry.assignee_ids.map((id) => memberNames.get(id)).filter(Boolean);
		if (names.length === 0) {
			return entry.assignee_ids.length === 1 ? '1 person' : `${entry.assignee_ids.length} people`;
		}
		const unknown = entry.assignee_ids.length - names.length;
		return unknown > 0 ? `${names.join(', ')} +${unknown}` : names.join(', ');
	}

	function recordHref(entry: ClientScheduleEntry) {
		if (entry.kind === 'visit') return resolve('/(app)/jobs/[id=uuid]', { id: entry.record_id });
		return resolve('/(app)/requests/[id=uuid]', { id: entry.record_id });
	}

	const columns: DataTableColumn[] = [
		{ key: 'schedule', label: 'Schedule' },
		{ key: 'title', label: 'Title' },
		{ key: 'assigned', label: 'Assigned' }
	];
</script>

{#if !denied}
	<SectionBlock title="Client schedule" icon={calendarIcon} level={2}>
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
			<LoadingSkeleton variant="table" label="Loading this client's schedule" rows={3} />
		{:else if scheduleQuery.isError}
			<ErrorState
				description="This client's schedule could not be loaded. Refresh and try again."
			/>
		{:else if entries.length === 0}
			<EmptyState
				icon={calendarIcon}
				title={view === 'upcoming' ? 'Nothing booked' : 'Nothing done yet'}
				description={view === 'upcoming'
					? 'Visits and assessments booked for this client will show up here.'
					: 'Visits and assessments completed for this client will show up here.'}
			/>
		{:else}
			<DataTable
				{columns}
				items={entries}
				rowId={(entry) => `${entry.kind}:${entry.id}`}
				caption={view === 'upcoming' ? 'Upcoming for this client' : 'Past for this client'}
			>
				{#snippet row(entry: ClientScheduleEntry)}
					<th scope="row">
						<span class="client-schedule__when">{whenLabel(entry)}</span>
						{#if entry.overdue}
							<Badge size="small" status="warning">Overdue</Badge>
						{/if}
					</th>
					<td>
						<div class="client-schedule__text">
							<a class="client-schedule__link" href={recordHref(entry)}>{entry.title}</a>
							<span class="client-schedule__record">{entry.record_label}</span>
						</div>
					</td>
					<td>{assignedLabel(entry)}</td>
				{/snippet}
				{#snippet footer()}
					{#if hasMore}
						<p class="client-schedule__more">
							{view === 'upcoming'
								? 'Showing the next ones only. Open a job to see all of its visits.'
								: 'Showing the latest ones only. Open a job to see all of its visits.'}
						</p>
					{/if}
				{/snippet}
			</DataTable>
		{/if}
	</SectionBlock>
{/if}

<style lang="scss">
	.client-schedule {
		&__when {
			margin-right: var(--space-small);
			color: var(--color-heading);
			font-weight: 700;
			white-space: nowrap;
		}

		&__text {
			display: flex;
			flex-direction: column;
			min-width: 0;
		}

		&__link {
			color: var(--color-heading);
			font-weight: 700;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__record {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__more {
			margin: 0;
			padding: var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: center;
		}
	}
</style>
