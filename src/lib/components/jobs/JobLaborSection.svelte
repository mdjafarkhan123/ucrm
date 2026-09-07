<script lang="ts">
	import { page } from '$app/state';
	import { createQuery } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import JobTimeEntryDialog from '$lib/components/jobs/JobTimeEntryDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		addJobTimeEntry,
		deleteJobTimeEntry,
		fetchJobLabor,
		jobLaborKey,
		updateJobTimeEntry,
		type JobTimeEntry,
		type JobTimeEntryInput,
		type JobVisit,
		type JobWriteError
	} from '$lib/jobs/api';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

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
		onChange
	}: {
		jobId: string;
		/** This job's visits, so an entry can be pinned to the one it was worked on. */
		visits?: JobVisit[];
		locale?: string;
		currencyCode?: string;
		/** Called after hours are recorded, corrected or removed, so the page can refresh the costing card. */
		onChange?: () => void;
	} = $props();

	const toast = getToastManager();
	const currentUserId = $derived((page.data.user?.id as string | undefined) ?? '');

	const laborQuery = createQuery(() => ({
		queryKey: jobLaborKey(jobId),
		queryFn: () => fetchJobLabor(jobId),
		enabled: Boolean(jobId),
		staleTime: 15_000
	}));
	const labor = $derived(laborQuery.data);
	const entries = $derived<JobTimeEntry[]>(labor?.entries ?? []);

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

	function openAdd() {
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
			onChange?.();
			toast.success('Hours removed');
		} catch (cause) {
			toast.error((cause as JobWriteError).message ?? 'Those hours could not be removed.');
		} finally {
			busyId = '';
		}
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
	{:else if entries.length === 0}
		<EmptyState
			icon={clockIcon}
			title="No hours recorded"
			description={labor?.can_track_team
				? 'Time worked on this job shows up here, with what it cost.'
				: 'Time you record on this job shows up here.'}
		/>
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
				no hourly cost, so those hours are not in the total. Set an hourly cost on the person's team profile
				— it applies to hours recorded from then on.
			</p>
		{/if}

		{#if labor?.has_more}
			<p class="job-labor__note">
				Showing the 200 most recent entries. The totals above count every one.
			</p>
		{/if}
	{/if}
</SectionBlock>

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

		&__item {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
				padding-top: var(--space-base);
			}

			&--busy {
				opacity: 0.5;
			}
		}

		&__body {
			display: flex;
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
