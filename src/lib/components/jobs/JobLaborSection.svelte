<script lang="ts">
	import { page } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import JobTimeEntryDialog from '$lib/components/jobs/JobTimeEntryDialog.svelte';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		addJobTimeEntry,
		deleteJobTimeEntry,
		fetchJobLabor,
		jobLaborKey,
		updateJobTimeEntry,
		type JobRunningTimer,
		type JobTimeEntry,
		type JobTimeEntryInput,
		type JobVisit,
		type JobWriteError
	} from '$lib/jobs/api';
	import { timesheetsKey } from '$lib/time-clock/timesheets';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// The hours worked on this job, the way Jobber's Labor block reads: who, how long, and what it cost us.
	// The section owns its own query rather than riding on the job payload, because who may see these rows —
	// and whether the money is on them at all — is a different question from who may open the job.
	//
	// Money here is never assembled in the browser. `job_labor` leaves the cost keys off a row entirely for a
	// reader without jobs.view_cost, so there is nothing to accidentally render.
	let {
		jobId,
		visits = [],
		locale = 'en-US',
		currencyCode = 'USD',
		embedded = false,
		onChange
	}: {
		jobId: string;
		/** This job's visits, so an entry can be pinned to the one it was worked on. */
		visits?: JobVisit[];
		locale?: string;
		currencyCode?: string;
		/** Classic Work log tab: rows only, no card of its own. The Work log draws the header and Add button. */
		embedded?: boolean;
		/** Called after hours are recorded, corrected or removed, so the page can refresh the costing card. */
		onChange?: () => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();
	const currentUserId = $derived((page.data.user?.id as string | undefined) ?? '');

	const laborQuery = createQuery(() => ({
		queryKey: jobLaborKey(jobId),
		queryFn: () => fetchJobLabor(jobId),
		enabled: Boolean(jobId),
		staleTime: 15_000
	}));
	const labor = $derived(laborQuery.data);
	const entries = $derived<JobTimeEntry[]>(labor?.entries ?? []);
	// Timers running on this job now. They have no hours or cost until they stop, so they sit above the list
	// and outside the totals.
	const running = $derived<JobRunningTimer[]>(labor?.running ?? []);
	// How far the server's clock is ahead of this device's when the hours were read.
	const offsetMs = $derived(labor ? Date.parse(labor.server_now) - laborQuery.dataUpdatedAt : 0);

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dateTimeFormat = $derived(
		new Intl.DateTimeFormat(locale, {
			day: 'numeric',
			month: 'short',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		})
	);
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);

	// Hours and minutes, never a decimal. "1h 30m" is how a timesheet is read out loud; 1.5 hours is how it
	// is added up, and this list is for reading.
	function duration(minutes: number) {
		const hours = Math.floor(minutes / 60);
		const rest = minutes % 60;
		if (hours === 0) return `${rest}m`;
		if (rest === 0) return `${hours}h`;
		return `${hours}h ${rest}m`;
	}

	// --- Recording and correcting ------------------------------------------------------------------------
	let dialogOpen = $state(false);
	let editing = $state<JobTimeEntry | null>(null);
	let saving = $state(false);
	let dialogError = $state('');

	export function openAdd() {
		editing = null;
		dialogError = '';
		dialogOpen = true;
	}

	function openEdit(entry: JobTimeEntry) {
		editing = entry;
		dialogError = '';
		dialogOpen = true;
	}

	function closeDialog() {
		if (saving) return;
		dialogOpen = false;
		editing = null;
	}

	async function save(input: JobTimeEntryInput) {
		if (saving) return;
		saving = true;
		dialogError = '';
		const correcting = editing;
		try {
			if (correcting) {
				const { user_id: _ignored, ...fields } = input;
				await updateJobTimeEntry(jobId, correcting.id, fields);
			} else {
				await addJobTimeEntry(jobId, input);
			}
			dialogOpen = false;
			editing = null;
			await laborQuery.refetch();
			// The same hours show on Timesheets (plan § Timesheets page: one set of hours in two places).
			void queryClient.invalidateQueries({ queryKey: timesheetsKey });
			onChange?.();
			toast.success(correcting ? 'Hours updated' : 'Hours recorded');
		} catch (cause) {
			const failure = cause as JobWriteError;
			dialogError = failure.fieldErrors?.form ?? failure.message;
		} finally {
			saving = false;
		}
	}

	// --- Removing --------------------------------------------------------------------------------------
	let confirmRemove = $state<JobTimeEntry | null>(null);
	let busyId = $state('');

	async function reallyRemove() {
		const entry = confirmRemove;
		if (!entry || busyId) return;
		busyId = entry.id;
		try {
			await deleteJobTimeEntry(jobId, entry.id);
			confirmRemove = null;
			await laborQuery.refetch();
			void queryClient.invalidateQueries({ queryKey: timesheetsKey });
			onChange?.();
			toast.success('Hours removed');
		} catch (cause) {
			toast.error((cause as JobWriteError).message ?? 'Those hours could not be removed.');
		} finally {
			busyId = '';
		}
	}

	// --- Classic Work log rows ----------------------------------------------------------------------------
	const timeFormat = $derived(
		new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' })
	);
	const dayFormat = $derived(
		new Intl.DateTimeFormat(locale, { weekday: 'short', month: 'short', day: 'numeric' })
	);
	const visitTitleById = $derived(new Map(visits.map((visit) => [visit.id, visit.title])));
	let showAll = $state(false);
	const visibleEntries = $derived(showAll ? entries : entries.slice(0, 4));

	function isToday(iso: string) {
		return new Date(iso).toDateString() === new Date().toDateString();
	}

	function context(startedAt: string, visitId: string | null) {
		const day = isToday(startedAt) ? 'Today' : dayFormat.format(new Date(startedAt));
		const visitTitle = visitId ? visitTitleById.get(visitId) : null;
		return visitTitle ? `${day} · ${visitTitle}` : day;
	}

	function range(entry: JobTimeEntry) {
		const start = new Date(entry.started_at);
		const end = new Date(start.getTime() + entry.minutes * 60_000);
		return `${timeFormat.format(start)} – ${timeFormat.format(end)}`;
	}

	function menuItems(entry: JobTimeEntry) {
		return [
			{ label: 'Edit hours', icon: pencilIcon, onSelect: () => openEdit(entry) },
			{
				label: 'Remove hours',
				icon: trashIcon,
				onSelect: () => (confirmRemove = entry),
				destructive: true
			}
		];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if embedded}
	{#if laborQuery.isPending}
		<div class="work-log__state">
			<LoadingSkeleton variant="text" label="Loading recorded hours" rows={3} />
		</div>
	{:else if laborQuery.isError}
		<p class="work-log__state">The hours on this job could not be loaded.</p>
	{:else if entries.length === 0 && running.length === 0}
		<div class="work-log__empty">
			<EmptyState
				icon={clockIcon}
				title="No hours recorded"
				description={labor?.can_track_team
					? 'Time worked on this job shows up here, with what it cost.'
					: 'Time you record on this job shows up here.'}
			/>
		</div>
	{:else}
		<ul class="work-log__rows">
			{#each running as timer (timer.user_id)}
				<li class="work-log__row">
					<Avatar id={timer.user_id} name={timer.user_name ?? '?'} size="base" />
					<div class="work-log__info">
						<p class="work-log__who">{timer.user_name ?? 'A team member'}</p>
						<p class="work-log__context">{context(timer.started_at, timer.visit_id)}</p>
					</div>
					<span class="work-log__range">{timeFormat.format(new Date(timer.started_at))} – now</span>
					<span class="work-log__figure work-log__figure--live">
						<span class="work-log__live-dot" aria-hidden="true"></span>
						<RunningClock startedAt={timer.started_at} {offsetMs} />
					</span>
					<span class="work-log__menu"></span>
				</li>
			{/each}
			{#each visibleEntries as entry (entry.id)}
				<li class="work-log__row" class:work-log__row--busy={busyId === entry.id}>
					<Avatar id={entry.user_id} name={entry.user_name ?? '?'} size="base" />
					<div class="work-log__info">
						<p class="work-log__who">{entry.user_name ?? 'A team member'}</p>
						<p class="work-log__context">
							{context(entry.started_at, entry.visit_id)}
							{#if entry.source === 'timer'}· From a timer{/if}
							{#if entry.approved}· Approved{/if}
						</p>
						{#if entry.notes}<p class="work-log__notes">{entry.notes}</p>{/if}
					</div>
					<span class="work-log__range">{range(entry)}</span>
					<span class="work-log__figure">
						{duration(entry.minutes)}
						{#if labor?.can_see_cost}
							<small class:work-log__unrated={entry.is_unrated}
								>{entry.is_unrated
									? 'No hourly cost'
									: money.format((entry.cost_total_minor ?? 0) / 100)}</small
							>
						{/if}
					</span>
					<span class="work-log__menu">
						{#if entry.can_edit}
							<DropdownMenu
								items={menuItems(entry)}
								triggerLabel="Time entry actions"
								disabled={busyId === entry.id}
							/>
						{/if}
					</span>
				</li>
			{/each}
		</ul>
		{#if labor?.can_see_cost && (labor?.totals.unrated_count ?? 0) > 0}
			<p class="work-log__band">
				{labor.totals.unrated_count === 1
					? 'One entry has'
					: `${labor.totals.unrated_count} entries have`}
				no hourly cost, so those hours are not in the total. Set an hourly cost on the person's team profile
				— it applies to hours recorded from then on.
			</p>
		{/if}
		<div class="work-log__footer">
			<span>
				{#if entries.length > visibleEntries.length}
					Showing {visibleEntries.length} of {labor?.totals.entry_count ?? entries.length} entries
				{:else}
					{labor?.can_track_team ? 'Total hours' : 'Your hours'}
					{duration(labor?.totals.minutes ?? 0)}
				{/if}
				{#if labor?.can_see_cost}
					· labor cost so far {money.format((labor.totals.cost_total_minor ?? 0) / 100)}
				{/if}
				{#if labor?.has_more}· the totals count every entry{/if}
			</span>
			{#if entries.length > 4}
				<button type="button" class="work-log__show" onclick={() => (showAll = !showAll)}>
					{showAll ? 'Show fewer' : 'Show all'}
					<span aria-hidden="true">{@html arrowRightIcon}</span>
				</button>
			{/if}
		</div>
	{/if}
{:else}
	<SectionBlock title="Labor" icon={clockIcon} level={2}>
		{#snippet actions()}
			{#if labor?.can_add}
				<Button variant="tertiary" size="small" onclick={openAdd}>Add time entry</Button>
			{/if}
		{/snippet}

		{#if laborQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading recorded hours" rows={3} />
		{:else if laborQuery.isError}
			<p class="job-labor__note">The hours on this job could not be loaded.</p>
		{:else if entries.length === 0 && running.length === 0}
			<EmptyState
				icon={clockIcon}
				title="No hours recorded"
				description={labor?.can_track_team
					? 'Time worked on this job shows up here, with what it cost.'
					: 'Time you record on this job shows up here.'}
			/>
		{:else}
			{#if running.length > 0}
				<ul class="job-labor job-labor--running" aria-label="Timers running now">
					{#each running as timer (timer.user_id)}
						<li class="job-labor__item">
							<div class="job-labor__body">
								<p class="job-labor__who">{timer.user_name ?? 'A team member'}</p>
								<p class="job-labor__when">
									Timer started {dateTimeFormat.format(new Date(timer.started_at))}
									{#if timer.visit_date}
										· Visit on {dateFormat.format(new Date(`${timer.visit_date}T12:00:00`))}
									{/if}
								</p>
							</div>
							<div class="job-labor__side">
								<RunningClock startedAt={timer.started_at} {offsetMs} />
							</div>
						</li>
					{/each}
				</ul>
			{/if}

			{#if entries.length === 0}
				<p class="job-labor__note">
					No hours recorded yet. A timer’s hours are added here when it stops.
				</p>
			{:else}
				<ul class="job-labor">
					{#each entries as entry (entry.id)}
						<li class="job-labor__item" class:job-labor__item--busy={busyId === entry.id}>
							<div class="job-labor__body">
								<p class="job-labor__who">
									{entry.user_name ?? 'A team member'}
									<span class="job-labor__duration">{duration(entry.minutes)}</span>
								</p>
								<p class="job-labor__when">
									{dateTimeFormat.format(new Date(entry.started_at))}
									{#if entry.visit_date}
										· Visit on {dateFormat.format(new Date(`${entry.visit_date}T12:00:00`))}
									{/if}
									{#if entry.source === 'timer'}· From a timer{/if}
									{#if entry.approved}· Approved{/if}
								</p>
								{#if entry.notes}<p class="job-labor__notes">{entry.notes}</p>{/if}
							</div>

							<div class="job-labor__side">
								{#if labor?.can_see_cost}
									{#if entry.is_unrated}
										<span class="job-labor__unrated">No hourly cost set</span>
									{:else}
										<span class="job-labor__cost"
											>{money.format((entry.cost_total_minor ?? 0) / 100)}</span
										>
									{/if}
								{/if}
								{#if entry.can_edit}
									<DropdownMenu
										items={menuItems(entry)}
										triggerLabel="Time entry actions"
										disabled={busyId === entry.id}
									/>
								{/if}
							</div>
						</li>
					{/each}
				</ul>

				<div class="job-labor__totals">
					<p class="job-labor__total">
						<span>{labor?.can_track_team ? 'Total hours' : 'Your hours'}</span>
						<strong>{duration(labor?.totals.minutes ?? 0)}</strong>
					</p>
					{#if labor?.can_see_cost}
						<p class="job-labor__total">
							<span>Labor cost</span>
							<strong>{money.format((labor.totals.cost_total_minor ?? 0) / 100)}</strong>
						</p>
					{/if}
				</div>

				{#if labor?.can_see_cost && (labor?.totals.unrated_count ?? 0) > 0}
					<p class="job-labor__note">
						{labor.totals.unrated_count === 1
							? 'One entry has'
							: `${labor.totals.unrated_count} entries have`}
						no hourly cost, so those hours are not in the total. Set an hourly cost on the person's team
						profile — it applies to hours recorded from then on.
					</p>
				{/if}

				{#if labor?.has_more}
					<p class="job-labor__note">
						Showing the 200 most recent entries. The totals above count every one.
					</p>
				{/if}
			{/if}
		{/if}
	</SectionBlock>
{/if}
<!-- eslint-enable svelte/no-at-html-tags -->

<JobTimeEntryDialog
	open={dialogOpen}
	entry={editing}
	{visits}
	{locale}
	canPickPerson={Boolean(labor?.can_track_team)}
	{currentUserId}
	{saving}
	error={dialogError}
	onSave={(input) => void save(input)}
	onClose={closeDialog}
/>

<ConfirmDialog
	open={confirmRemove !== null}
	title="Remove these hours?"
	confirmLabel="Remove hours"
	destructive
	loading={busyId !== '' && busyId === confirmRemove?.id}
	onConfirm={() => void reallyRemove()}
	onClose={() => {
		if (!busyId) confirmRemove = null;
	}}
>
	This takes the hours off the job and its cost. A record of the removal is kept in the job's
	costing history.
</ConfirmDialog>

<style lang="scss">
	.job-labor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		/* On a phone the cost and menu drop below the entry rather than squeezing it into a narrow column. */
		&__item {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
				padding-top: var(--space-base);
			}

			&--busy {
				opacity: 0.5;
			}
		}

		/* Running timers sit above the recorded hours, ruled off from them. */
		&--running {
			margin-bottom: var(--space-base);
			padding-bottom: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		&__body {
			display: flex;
			flex: 1 1 16rem;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__who {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__duration {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__when,
		&__notes {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__notes {
			color: var(--color-text);
		}

		&__side {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			flex-shrink: 0;
			margin-left: auto;
		}

		&__cost {
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}

		&__unrated {
			color: var(--color-warning);
			font-size: var(--typography--fontSize-small);
		}

		&__totals {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			padding-top: var(--space-base);
		}

		&__total {
			display: flex;
			align-items: baseline;
			gap: var(--space-small);
			margin: 0;

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			strong {
				color: var(--color-heading);
				font-variant-numeric: tabular-nums;
			}
		}
	}

	.job-labor__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
