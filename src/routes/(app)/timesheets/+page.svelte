<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import type { ResolvedPathname } from '$app/types';
	import CalendarBar from '$lib/components/calendar/CalendarBar.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import ApproveTimesheetsDialog from '$lib/components/time-clock/ApproveTimesheetsDialog.svelte';
	import StopTimerDialog from '$lib/components/time-clock/StopTimerDialog.svelte';
	import TimeEntryHistoryDialog from '$lib/components/time-clock/TimeEntryHistoryDialog.svelte';
	import TimesheetEntryDialog from '$lib/components/time-clock/TimesheetEntryDialog.svelte';
	import TimesheetPersonRow from '$lib/components/time-clock/TimesheetPersonRow.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import FilterChipMulti from '$lib/components/ui/FilterChipMulti.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { scheduleWindow } from '$lib/schedule/filters';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { durationLabel } from '$lib/time-clock/api';
	import {
		approvalPreviewKey,
		defaultCutoff,
		fetchApprovalPreview
	} from '$lib/time-clock/approval';
	import {
		clockInMember,
		deleteTimesheetEntry,
		entryHistoryKey,
		fetchEntryHistory,
		refreshAfterCorrection,
		type CorrectionError,
		type EntryDialogMode,
		type StopTarget,
		type TimesheetEntryActions
	} from '$lib/time-clock/corrections';
	import {
		clockTime,
		dayTotals,
		entryPurpose,
		fetchTimesheetSummary,
		personName,
		readTimesheetFilters,
		runningPurpose,
		shiftTimesheetDate,
		timesheetDays,
		timesheetFilterParams,
		timesheetRangeLabel,
		timesheetSummaryKey,
		timesheetWarnings,
		visiblePeople,
		type TimesheetEntry,
		type TimesheetFilters,
		type TimesheetPerson,
		type TimesheetSpan
	} from '$lib/time-clock/timesheets';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import clockPlayIcon from '@tabler/icons/outline/clock-play.svg?raw';
	import clockStopIcon from '@tabler/icons/outline/clock-stop.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import clockPageIcon from '@tabler/icons/outline/clock.svg?raw';

	// Timesheets (docs/time-clock-behavior-contract.md § Timesheets page): who worked how long, for a day or a
	// Sunday-to-Saturday week. One row per person; opening a row lists their entries. People limited to their
	// own time see only themselves, with their row already open.

	// The URL is the page's memory: the view, the day and the chosen people. A plain /timesheets link opens on
	// this week; "today" is the business's, which only the server knows, so a missing date is left to it.
	const filters = $derived(readTimesheetFilters(page.url.searchParams));

	const summaryQuery = createQuery(() => ({
		queryKey: timesheetSummaryKey(filters.span, filters.date),
		queryFn: () => fetchTimesheetSummary(filters.span, filters.date),
		staleTime: 30_000
	}));

	const summary = $derived(summaryQuery.data);
	const days = $derived(summary ? timesheetDays(summary) : []);
	// The day the arrows and the date picker start from: the one in the URL, else the business's today.
	const anchor = $derived(filters.date ?? summary?.today ?? null);
	const offsetMs = $derived(
		summary ? Date.parse(summary.server_now) - summaryQuery.dataUpdatedAt : 0
	);

	// The window is worked out here as soon as the date is known, so the heading moves with the arrows
	// instead of waiting for the read.
	const rangeLabel = $derived.by(() => {
		if (filters.date) {
			const window = scheduleWindow(filters.date, filters.span);
			return timesheetRangeLabel(filters.span, window.from, window.to);
		}
		if (summary) return timesheetRangeLabel(summary.span, summary.from, summary.to);
		return filters.span === 'day' ? 'Today' : 'This week';
	});

	const teamView = $derived(summary?.can_view_team ?? false);
	const shown = $derived(summary ? visiblePeople(summary.people, filters.people) : []);
	const warnings = $derived(timesheetWarnings(shown));
	const totals = $derived(dayTotals(shown, days));
	const grandTotal = $derived(shown.reduce((sum, person) => sum + person.total_minutes, 0));

	// The people filter offers this window's roster. Someone chosen who is not on it stays in the URL, so
	// stepping to a week they worked brings them back, but is never shown as a raw id.
	const peopleOptions = $derived(
		(summary?.people ?? []).map((person) => ({ value: person.user_id, label: personName(person) }))
	);
	const chosenHere = $derived(
		filters.people.filter((id) => peopleOptions.some((option) => option.value === id))
	);

	function changePeople(next: string[]) {
		const elsewhere = filters.people.filter(
			(id) => !peopleOptions.some((option) => option.value === id)
		);
		applyFilters({ ...filters, people: [...elsewhere, ...next] });
	}

	// Rows opened by hand. Someone who sees only themselves starts with their own row open.
	let toggled = $state<Record<string, boolean>>({});

	function isOpen(userId: string) {
		return toggled[userId] ?? !teamView;
	}

	function applyFilters(next: TimesheetFilters) {
		const query = timesheetFilterParams(next).toString();
		const route: string = resolve('/(app)/timesheets');
		const destination = (query ? `${route}?${query}` : route) as ResolvedPathname;
		// Each change is its own history entry, so Back steps through the weeks the way it steps through pages.
		void goto(destination, { keepFocus: true, noScroll: true });
	}

	function step(direction: -1 | 1) {
		if (!anchor) return;
		applyFilters({ ...filters, date: shiftTimesheetDate(anchor, filters.span, direction) });
	}

	// --- Corrections (plan § Timesheets page: Add entry, Edit or delete, Edit history, Manager actions) --------
	// One of each dialog for the whole page; a person's row or entry menu says which entry or person it is for.
	// What each menu offers follows what the database said the reader may do.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const me = $derived(summary?.people.find((person) => person.is_me) ?? null);
	// Whose hours a manager may add: anyone still on the team.
	const teamOptions = $derived(
		(summary?.people ?? [])
			.filter((person) => person.status === 'active' || person.status === 'deactivated')
			.map((person) => ({ value: person.user_id, label: personName(person) }))
	);

	let entryDialog = $state<EntryDialogMode | null>(null);
	let historyEntry = $state<TimesheetEntry | null>(null);
	let stopTarget = $state<StopTarget | null>(null);
	let deleting = $state<TimesheetEntry | null>(null);
	let deletePending = $state(false);
	let approving = $state(false);

	// Approve starts on the last day being looked at, never after today. What is waiting up to then is read
	// when the button is pointed at, so the dialog usually opens with it.
	const approvalCutoff = $derived(summary ? defaultCutoff(summary.to, summary.today) : '');

	function warmApproval() {
		if (!approvalCutoff) return;
		void queryClient.prefetchQuery({
			queryKey: approvalPreviewKey(approvalCutoff),
			queryFn: () => fetchApprovalPreview(approvalCutoff),
			staleTime: 15_000
		});
	}

	// A new entry starts on the day being looked at: the Day view's day, or today when this week holds it.
	function defaultDay() {
		if (!summary) return '';
		if (summary.span === 'day') return summary.from;
		return summary.today >= summary.from && summary.today <= summary.to
			? summary.today
			: summary.from;
	}

	function addEntry(userId: string) {
		entryDialog = { kind: 'add', userId, day: defaultDay() };
	}

	function stopFor(person: TimesheetPerson) {
		if (!person.running) return;
		stopTarget = {
			userId: person.user_id,
			name: person.is_me ? 'You' : personName(person),
			startedAt: person.running.started_at,
			clockedIn: person.running.clocked_in,
			overADay: person.running.over_a_day,
			what: runningPurpose(person.running)
		};
	}

	async function clockIn(person: TimesheetPerson) {
		try {
			const result = await clockInMember(person.user_id);
			await refreshAfterCorrection(queryClient);
			toast.success(
				result.paused_by_visit
					? `${personName(person)} is clocked in. Their visit timer keeps running first.`
					: `${personName(person)} is clocked in`
			);
		} catch (cause) {
			toast.error((cause as CorrectionError).message);
		}
	}

	function personMenu(person: TimesheetPerson) {
		if (!summary) return [];
		const items = [];
		// Adding for someone else needs the team's time; for oneself, one's own.
		if (summary.can_add && (teamView || person.is_me) && person.status !== 'removed') {
			items.push({ label: 'Add entry', icon: plusIcon, onSelect: () => addEntry(person.user_id) });
		}
		if (teamView && person.status === 'active' && !person.running?.clocked_in) {
			items.push({ label: 'Clock in', icon: clockPlayIcon, onSelect: () => void clockIn(person) });
		}
		if (person.running && (teamView || (person.is_me && summary.can_add))) {
			items.push({
				label: person.running.over_a_day
					? 'Set end time'
					: person.running.clocked_in
						? 'Clock out…'
						: 'Stop timer…',
				icon: clockStopIcon,
				onSelect: () => stopFor(person)
			});
		}
		return items;
	}

	const entryActions: TimesheetEntryActions = {
		edit: (entry, userId) => {
			entryDialog = entry.is_running
				? { kind: 'running', entry, userId }
				: { kind: 'edit', entry, userId };
		},
		stop: (_entry, userId) => {
			const person = summary?.people.find((candidate) => candidate.user_id === userId);
			if (person) stopFor(person);
		},
		history: (entry) => (historyEntry = entry),
		remove: (entry) => (deleting = entry),
		warm: (entry) =>
			void queryClient.prefetchQuery({
				queryKey: entryHistoryKey(entry.id),
				queryFn: () => fetchEntryHistory(entry.id),
				staleTime: 15_000
			})
	};

	function entryHeading(entry: TimesheetEntry) {
		return `${entryPurpose(entry)} · ${formatCalendarDay(entry.started_on, {
			weekday: 'short',
			month: 'short',
			day: 'numeric'
		})}`;
	}

	async function confirmDelete() {
		if (!deleting || deletePending) return;
		deletePending = true;
		try {
			await deleteTimesheetEntry(deleting.id);
			await refreshAfterCorrection(queryClient);
			toast.success('Entry deleted');
			deleting = null;
		} catch (cause) {
			toast.error((cause as CorrectionError).message);
		} finally {
			deletePending = false;
		}
	}

	const viewOptions: { value: TimesheetSpan; label: string }[] = [
		{ value: 'day', label: 'Day' },
		{ value: 'week', label: 'Week' }
	];
</script>

<svelte:head
	><title>{summary && !teamView ? 'My Timesheets' : 'Timesheets'} · UpliftContractor</title
	></svelte:head
>

<PageContainer variant="fill">
	<PageHeader
		icon={clockPageIcon}
		tone="time"
		title="Timesheets"
		description={summary && !teamView
			? 'Your hours, from your timers and hours added on Jobs.'
			: 'Who worked how long, from timers and hours added on Jobs.'}
	>
		{#snippet actions()}
			{#if summary?.can_approve}
				<span
					class="timesheets__approve"
					role="presentation"
					onpointerenter={warmApproval}
					onfocusin={warmApproval}
				>
					<Button variant="secondary" onclick={() => (approving = true)}>Approve</Button>
				</span>
			{/if}
			{#if summary?.can_add && (teamView || me)}
				<Button variant="primary" onclick={() => addEntry(me?.user_id ?? '')}>Add entry</Button>
			{/if}
		{/snippet}
	</PageHeader>

	<div class="timesheets">
		<CalendarBar
			view={filters.span}
			views={viewOptions}
			{rangeLabel}
			onstep={step}
			ontoday={() => applyFilters({ ...filters, date: null })}
			onview={(span) => applyFilters({ ...filters, span })}
		>
			{#snippet extras()}
				<CalendarPicker
					id="timesheets-date"
					label="Go to date"
					hideLabel
					size="small"
					class="timesheets__date"
					value={calendarDateFromString(anchor)}
					onchange={(value) => {
						const date = calendarDateToString(value);
						if (date) applyFilters({ ...filters, date });
					}}
				/>
				{#if teamView && peopleOptions.length > 1}
					<FilterChipMulti
						id="timesheets-people"
						label="People"
						options={peopleOptions}
						values={chosenHere}
						size="small"
						onchange={changePeople}
					/>
				{/if}
			{/snippet}
		</CalendarBar>

		{#if summaryQuery.isPending}
			<LoadingSkeleton variant="table" rows={5} label="Loading timesheets" />
		{:else if summaryQuery.isError || !summary}
			<ErrorState
				title="Timesheets could not be loaded"
				description={summaryQuery.error?.message &&
				summaryQuery.error.message !== 'Timesheets could not be loaded.'
					? summaryQuery.error.message
					: 'Check your connection, then try again.'}
				retry={() => void summaryQuery.refetch()}
			/>
		{:else if summary.people.length === 0}
			<EmptyState
				icon={clockIcon}
				title={teamView ? 'No one records time yet' : 'No hours here yet'}
				description={teamView
					? 'Team members appear here once they can start timers, or when hours are added for them on a Job.'
					: 'Hours from your timers, and hours added for you on Jobs, appear here.'}
			/>
		{:else if shown.length === 0}
			<EmptyState
				icon={usersIcon}
				title="None of the chosen people are on this timesheet"
				description="They have no hours here and cannot run timers right now."
			>
				{#snippet action()}
					<Button variant="secondary" onclick={() => applyFilters({ ...filters, people: [] })}>
						Show everyone
					</Button>
				{/snippet}
			</EmptyState>
		{:else}
			{#if warnings.length > 0}
				<Banner type="warning">
					{warnings.join(' ')} Open a row to check the entries.
				</Banner>
			{/if}

			<div class="timesheets__table-wrap">
				<table class="timesheets__table timesheets__table--{summary.span}">
					<caption class="timesheets__caption">
						{summary.span === 'week' ? 'Hours by day for' : 'Hours on'}
						{rangeLabel}
					</caption>
					<thead>
						<tr>
							<th scope="col" class="timesheets__person-heading">
								{teamView ? `People (${shown.length})` : 'Person'}
							</th>
							{#if summary.span === 'week'}
								{#each days as day (day)}
									<th
										scope="col"
										class="timesheets__day-heading"
										class:timesheets__day-heading--today={day === summary.today}
									>
										<abbr
											title={formatCalendarDay(day, {
												weekday: 'long',
												month: 'long',
												day: 'numeric'
											})}
										>
											<span class="timesheets__weekday"
												>{formatCalendarDay(day, { weekday: 'short' })}</span
											>
											<span class="timesheets__date-number"
												>{formatCalendarDay(day, { day: 'numeric' })}</span
											>
										</abbr>
									</th>
								{/each}
							{:else}
								<th scope="col" class="timesheets__number-heading">Entries</th>
							{/if}
							<th scope="col" class="timesheets__number-heading">Total</th>
						</tr>
					</thead>
					<tbody>
						{#each shown as person (person.user_id)}
							<TimesheetPersonRow
								{person}
								span={summary.span}
								{days}
								from={summary.from}
								to={summary.to}
								timezone={summary.timezone}
								{offsetMs}
								open={isOpen(person.user_id)}
								{teamView}
								menu={personMenu(person)}
								{entryActions}
								ontoggle={() => (toggled[person.user_id] = !isOpen(person.user_id))}
							/>
						{/each}
					</tbody>
					{#if shown.length > 1}
						<tfoot>
							<tr class="timesheets__totals">
								<th scope="row">Total</th>
								{#if summary.span === 'week'}
									{#each days as day, index (day)}
										<td>
											<span class="timesheets__totals-name"
												>{formatCalendarDay(day, { weekday: 'short' })}</span
											>
											{totals[index] > 0 ? durationLabel(totals[index]) : '–'}
										</td>
									{/each}
								{:else}
									<td></td>
								{/if}
								<td class="timesheets__grand-total">{durationLabel(grandTotal)}</td>
							</tr>
						</tfoot>
					{/if}
				</table>
			</div>

			<p class="timesheets__note">
				Running timers count once they stop. Times are in {summary.timezone.replaceAll('_', ' ')} time.
			</p>
		{/if}
	</div>
</PageContainer>

{#if summary}
	<TimesheetEntryDialog
		open={entryDialog !== null}
		mode={entryDialog}
		timezone={summary.timezone}
		people={teamOptions}
		canPickPerson={teamView}
		onClose={() => (entryDialog = null)}
	/>
	<TimeEntryHistoryDialog
		open={historyEntry !== null}
		entryId={historyEntry?.id ?? null}
		heading={historyEntry ? entryHeading(historyEntry) : ''}
		onClose={() => (historyEntry = null)}
	/>
	<ApproveTimesheetsDialog
		open={approving}
		initialCutoff={approvalCutoff}
		today={summary.today}
		timezone={summary.timezone}
		onClose={() => (approving = false)}
	/>
	<StopTimerDialog
		open={stopTarget !== null}
		target={stopTarget}
		timezone={summary.timezone}
		onClose={() => (stopTarget = null)}
	/>
	<ConfirmDialog
		open={deleting !== null}
		title="Delete this entry?"
		icon={trashIcon}
		tone="critical"
		destructive
		confirmLabel="Delete entry"
		loading={deletePending}
		onConfirm={() => void confirmDelete()}
		onClose={() => !deletePending && (deleting = null)}
	>
		{#if deleting}
			<p>
				<strong>{entryHeading(deleting)}</strong>,
				{clockTime(deleting.started_at, summary.timezone)}
				{#if deleting.ended_at}– {clockTime(deleting.ended_at, summary.timezone)}{/if}
				{#if deleting.minutes !== null}({durationLabel(deleting.minutes)}){/if}
			</p>
			<p class="timesheets__delete-note">
				The hours come off Timesheets{deleting.kind === 'job' ? ' and the job’s labour cost' : ''}.
				The edit history keeps a record of what was deleted and by whom.
			</p>
		{/if}
	</ConfirmDialog>
{/if}

<style lang="scss">
	.timesheets {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.timesheets__approve {
		display: contents;
	}

	:global(.timesheets__date) {
		width: 11rem;
	}

	.timesheets__table-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
	}

	.timesheets__table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);

		thead th {
			padding: var(--space-slim) var(--space-small);
			border-bottom: var(--border-base) solid var(--color-border);
			background-color: var(--color-surface--background--subtle);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			white-space: nowrap;

			&:first-child {
				padding-left: var(--space-base);
			}

			&:last-child {
				padding-right: var(--space-large);
			}
		}

		/* The last person's bottom border would double the wrapper's. */
		:global(tbody > tr:last-child > *) {
			border-bottom: 0;
		}
	}

	.timesheets__caption {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}

	.timesheets__person-heading {
		text-align: left;
	}

	.timesheets__day-heading,
	.timesheets__number-heading {
		text-align: right;
	}

	.timesheets__day-heading {
		width: 5.5rem;

		abbr {
			display: inline-flex;
			flex-direction: column;
			align-items: flex-end;
			text-decoration: none;
		}

		&--today {
			color: var(--color-interactive) !important;
		}
	}

	.timesheets__weekday {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		text-transform: uppercase;

		.timesheets__day-heading--today & {
			color: var(--color-interactive);
		}
	}

	.timesheets__date-number {
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.timesheets__number-heading {
		width: 7rem;
	}

	.timesheets__totals {
		th,
		td {
			padding: var(--space-base) var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
			background-color: var(--color-surface--background--subtle);
			color: var(--color-heading);
			font-variant-numeric: tabular-nums;
			font-weight: 600;
			text-align: right;
			white-space: nowrap;
		}

		th {
			padding-left: var(--space-base);
			text-align: left;
		}

		td:last-child {
			padding-right: var(--space-large);
		}
	}

	.timesheets__totals-name {
		display: none;
	}

	.timesheets__grand-total {
		font-weight: 800 !important;
	}

	.timesheets__delete-note {
		margin-top: var(--space-small);
	}

	.timesheets__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	/* On a phone each person is a card-like block (see TimesheetPersonRow); the column headings give way to the
	   day names each cell carries, and the totals row reads the same way. */
	@media (max-width: 639px) {
		.timesheets__table-wrap {
			overflow-x: visible;
		}

		.timesheets__table {
			display: block;

			thead {
				display: none;
			}

			tbody,
			tfoot {
				display: block;
			}
		}

		.timesheets__totals {
			display: grid;
			grid-template-columns: repeat(7, minmax(0, 1fr));
			row-gap: var(--space-small);
			padding: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background-color: var(--color-surface--background--subtle);

			th,
			td {
				padding: 0;
				border-top: 0;
				background: transparent;
			}

			th {
				grid-row: 1;
				grid-column: 1 / 6;
			}

			td {
				display: flex;
				flex-direction: column;
				align-items: center;
				gap: var(--space-minuscule);
				padding: var(--space-smaller) 0;
				font-size: var(--typography--fontSize-small);
				line-height: var(--typography--lineHeight-tighter);
				align-self: start;
				text-align: center;
				white-space: normal;
			}

			td:last-child {
				grid-row: 1;
				grid-column: 6 / 8;
				display: block;
				padding: 0;
				font-size: var(--typography--fontSize-base);
				text-align: right;
			}
		}

		.timesheets__table--day .timesheets__totals {
			grid-template-columns: minmax(0, 1fr) auto;

			th {
				grid-column: 1;
			}

			td:not(:last-child) {
				display: none;
			}

			td:last-child {
				grid-column: 2;
			}
		}

		.timesheets__totals-name {
			display: block;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 400;
		}
	}
</style>
