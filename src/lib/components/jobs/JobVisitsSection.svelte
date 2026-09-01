<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import CreateVisitsDialog from '$lib/components/jobs/CreateVisitsDialog.svelte';
	import JobVisitDialog from '$lib/components/jobs/JobVisitDialog.svelte';
	import EditAllVisitsDialog from '$lib/components/jobs/EditAllVisitsDialog.svelte';
	import ApplyToFutureDialog from '$lib/components/jobs/ApplyToFutureDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import type { JobType } from '$lib/jobs/statuses';
	import {
		addJobVisits,
		applyVisitToFuture,
		deleteJobVisit,
		jobCountsKey,
		jobDetailKey,
		jobEventsKey,
		moveJobVisits,
		rescheduleJobVisits,
		updateJobVisit,
		type AddVisitInput,
		type JobRecurrenceInput,
		type JobVisit,
		type JobWriteError,
		type UpdateVisitInput
	} from '$lib/jobs/api';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// The persisted visits manager for a job's detail page — the same "child record with its own save" shape
	// as a client's property: every action here writes for itself and reports its own toast, so the page's
	// title/instructions draft never has to know visits exist.
	let {
		jobId,
		visits,
		jobTitle = '',
		locale = 'en-US',
		canSchedule,
		jobType,
		isAsNeeded,
		recurrence,
		jobRevision
	}: {
		jobId: string;
		visits: JobVisit[];
		jobTitle?: string;
		locale?: string;
		canSchedule: boolean;
		jobType: JobType;
		isAsNeeded: boolean;
		// The job's repeat rule, present only for a recurring scheduled job. "Edit all visits" opens on it.
		recurrence: JobRecurrenceInput | null;
		// The job's own lock token — the reschedule command guards on it, exactly like saving the details does.
		jobRevision: number;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Only a recurring job that is not as-needed has a repeating schedule to edit or to carry forward. A
	// one-off's visits are each their own, and an as-needed job is dispatched when work comes up.
	const isRecurringScheduled = $derived(jobType === 'recurring' && !isAsNeeded);

	// The edit dialog's "Assigned team" list is revealed content — it must not load with the page. Warm it
	// the moment the pointer lands on a visit row (or the row menu opens), so the fetch is usually done
	// before "Edit" is clicked; the result is cached for reuse. `prefetchQuery` dedupes and respects
	// staleTime, so repeated hovers are free.
	function warmTeam() {
		void queryClient.prefetchQuery({
			queryKey: assignableTeamKey,
			queryFn: fetchAssignableTeam,
			staleTime: 5 * 60 * 1000
		});
	}

	// FNV-1a over the ordered payload, the same fingerprint JobForm uses, so a retried request is recognised
	// as a replay of the same intent rather than a second write.
	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	async function refreshAll() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: jobDetailKey(jobId) }),
			queryClient.invalidateQueries({ queryKey: jobEventsKey(jobId) }),
			queryClient.invalidateQueries({ queryKey: ['jobs', 'list'] }),
			queryClient.invalidateQueries({ queryKey: jobCountsKey })
		]);
	}

	// --- Formatting ---------------------------------------------------------------------------------------

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	const timeFormat = $derived(
		new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' })
	);

	function formatTime(value: string) {
		return timeFormat.format(new Date(`2000-01-01T${value}`));
	}

	function visitWhen(visit: JobVisit) {
		if (!visit.visit_date) return 'Unscheduled';
		const day = dateFormat.format(new Date(`${visit.visit_date}T00:00`));
		if (!visit.start_time) return `${day} · Anytime`;
		const start = formatTime(visit.start_time);
		if (visit.end_time) return `${day} · ${start}–${formatTime(visit.end_time)}`;
		return `${day} · ${start}`;
	}

	// --- Add visits ----------------------------------------------------------------------------------------

	let creating = $state(false);
	let addSaving = $state(false);
	let addError = $state('');

	async function runAdd(items: AddVisitInput[], successLabel: string) {
		addSaving = true;
		addError = '';
		try {
			await addJobVisits(jobId, items, crypto.randomUUID(), fingerprint(items));
			await refreshAll();
			toast.success(successLabel);
		} catch (caught) {
			addError = (caught as JobWriteError).message ?? 'Those visits could not be added.';
		} finally {
			addSaving = false;
		}
	}

	function handleCreate(result: { dates: string[]; scheduleLater: boolean }) {
		creating = false;
		const items: AddVisitInput[] = result.scheduleLater
			? [
					{
						visit_date: null,
						start_time: null,
						end_time: null,
						all_day: false,
						title: null,
						instructions: null,
						assignee_ids: [],
						source: 'manual'
					}
				]
			: result.dates.map((date) => ({
					visit_date: date,
					start_time: null,
					end_time: null,
					all_day: true,
					title: null,
					instructions: null,
					assignee_ids: [],
					source: 'manual'
				}));
		void runAdd(items, items.length === 1 ? 'Visit added' : `${items.length} visits added`);
	}

	function duplicateVisit(visit: JobVisit) {
		const item: AddVisitInput = {
			visit_date: visit.visit_date,
			start_time: visit.start_time,
			end_time: visit.end_time,
			all_day: visit.all_day,
			title: visit.title,
			instructions: visit.instructions,
			assignee_ids: [...visit.assignee_ids],
			source: 'duplicated'
		};
		void runAdd([item], 'Visit duplicated');
	}

	// --- Edit one visit --------------------------------------------------------------------------------------

	let editVisit = $state<JobVisit | null>(null);
	let editSaving = $state(false);
	let editError = $state('');

	async function saveEdit(payload: UpdateVisitInput) {
		if (!editVisit) return;
		editSaving = true;
		editError = '';
		try {
			await updateJobVisit(jobId, editVisit.id, editVisit.revision, payload);
			editVisit = null;
			await refreshAll();
			toast.success('Visit saved');
		} catch (caught) {
			const err = caught as JobWriteError;
			if (err.reason === 'stale' || err.reason === 'locked') {
				editVisit = null;
				await refreshAll();
				toast.error(
					err.message ?? 'Someone else changed this visit. The latest version is now on screen.'
				);
			} else {
				editError = err.fieldErrors?.form ?? err.message ?? 'That visit could not be saved.';
			}
		} finally {
			editSaving = false;
		}
	}

	// --- Save one visit, then push its settings forward ------------------------------------------------------

	// "Save and update future visits" on a recurring job's visit. The visit saves first, then the section
	// offers the follow-up dialog seeded with this visit. The dialog's own text and the command both measure
	// "later" from this visit's day, so a backlog visit never reaches here — the button is hidden for one.
	let applyTarget = $state<{ visitId: string; label: string; date: string } | null>(null);
	let applySaving = $state(false);
	let applyError = $state('');

	// The same rule the command uses: a later visit is a dated, incomplete one strictly after this visit's day.
	// The other visits' days do not move when this one saves, so this count is right whatever the refetch does.
	const applyLaterCount = $derived(
		applyTarget
			? visits.filter(
					(visit) =>
						visit.id !== applyTarget!.visitId &&
						!visit.completed_at &&
						visit.visit_date !== null &&
						visit.visit_date > applyTarget!.date
				).length
			: 0
	);

	async function saveEditThenFuture(payload: UpdateVisitInput) {
		if (!editVisit) return;
		// No day to measure "later" from, so there is nothing to carry forward — save it like any other edit.
		if (payload.visit_date === null) {
			await saveEdit(payload);
			return;
		}
		const target = editVisit;
		editSaving = true;
		editError = '';
		try {
			await updateJobVisit(jobId, target.id, target.revision, payload);
			editVisit = null;
			await refreshAll();
			toast.success('Visit saved');
			applyTarget = {
				visitId: target.id,
				label: target.title?.trim() || jobTitle.trim() || 'this visit',
				date: payload.visit_date
			};
		} catch (caught) {
			const err = caught as JobWriteError;
			if (err.reason === 'stale' || err.reason === 'locked') {
				editVisit = null;
				await refreshAll();
				toast.error(
					err.message ?? 'Someone else changed this visit. The latest version is now on screen.'
				);
			} else {
				editError = err.fieldErrors?.form ?? err.message ?? 'That visit could not be saved.';
			}
		} finally {
			editSaving = false;
		}
	}

	async function confirmApplyFuture(fields: { time_of_day: boolean; assigned_team: boolean }) {
		if (!applyTarget) return;
		applySaving = true;
		applyError = '';
		try {
			const result = await applyVisitToFuture(
				jobId,
				applyTarget.visitId,
				fields,
				crypto.randomUUID(),
				fingerprint(fields)
			);
			applyTarget = null;
			await refreshAll();
			const count = result.updated_count;
			toast.success(count === 1 ? '1 later visit updated' : `${count} later visits updated`);
		} catch (caught) {
			applyError =
				(caught as JobWriteError).message ??
				'Those settings could not be applied to the later visits.';
		} finally {
			applySaving = false;
		}
	}

	// --- Edit all visits (recurring schedule) ----------------------------------------------------------------

	let editingAll = $state(false);
	let rescheduleSaving = $state(false);
	let rescheduleError = $state('');

	async function saveReschedule(rule: JobRecurrenceInput) {
		rescheduleSaving = true;
		rescheduleError = '';
		try {
			const result = await rescheduleJobVisits(
				jobId,
				jobRevision,
				rule,
				crypto.randomUUID(),
				fingerprint(rule)
			);
			editingAll = false;
			await refreshAll();
			const created = result.created_count;
			const removed = result.removed_count;
			const createdLabel = `${created} ${created === 1 ? 'visit' : 'visits'}`;
			toast.success(
				removed > 0
					? `Schedule updated — ${createdLabel} scheduled, ${removed} old ${removed === 1 ? 'one' : 'ones'} cleared`
					: `Schedule updated — ${createdLabel} scheduled`
			);
		} catch (caught) {
			const err = caught as JobWriteError;
			if (err.reason === 'stale' || err.reason === 'locked') {
				editingAll = false;
				await refreshAll();
				toast.error(
					err.message ?? 'Someone else changed this job. The latest version is now on screen.'
				);
			} else {
				rescheduleError =
					err.fieldErrors?.form ?? err.message ?? 'That schedule could not be saved.';
			}
		} finally {
			rescheduleSaving = false;
		}
	}

	// --- Delete one visit ------------------------------------------------------------------------------------

	let deleteTarget = $state<JobVisit | null>(null);
	let deleting = $state(false);

	async function confirmDelete() {
		if (!deleteTarget) return;
		deleting = true;
		try {
			await deleteJobVisit(jobId, deleteTarget.id, deleteTarget.revision);
			deleteTarget = null;
			await refreshAll();
			toast.success('Visit deleted');
		} catch (caught) {
			const err = caught as JobWriteError;
			toast.error(err.message ?? 'That visit could not be removed.');
			if (err.reason === 'stale' || err.reason === 'locked') await refreshAll();
			deleteTarget = null;
		} finally {
			deleting = false;
		}
	}

	// --- Bulk move ---------------------------------------------------------------------------------------

	let selectedIds = $state<Set<string>>(new Set());
	let moveDays = $state(1);
	let moving = $state(false);

	// Only an incomplete, dated visit can move by a number of days — a backlog visit has no day to shift.
	function canSelect(visit: JobVisit) {
		return !visit.completed_at && visit.visit_date !== null;
	}

	function toggleSelect(id: string, checked: boolean) {
		const next = new Set(selectedIds);
		if (checked) next.add(id);
		else next.delete(id);
		selectedIds = next;
	}

	function clearSelection() {
		selectedIds = new Set();
	}

	async function moveSelected() {
		if (selectedIds.size === 0 || !moveDays) return;
		moving = true;
		try {
			const ids = [...selectedIds];
			await moveJobVisits(
				jobId,
				ids,
				moveDays,
				crypto.randomUUID(),
				fingerprint({ ids, moveDays })
			);
			clearSelection();
			await refreshAll();
			toast.success(ids.length === 1 ? '1 visit moved' : `${ids.length} visits moved`);
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'Those visits could not be moved.');
		} finally {
			moving = false;
		}
	}

	function rowMenuItems(visit: JobVisit) {
		const items: {
			label: string;
			icon?: string;
			onSelect: () => void;
			destructive?: boolean;
		}[] = [];
		if (!visit.completed_at) {
			items.push({ label: 'Edit', icon: pencilIcon, onSelect: () => (editVisit = visit) });
		}
		items.push({ label: 'Duplicate', icon: copyIcon, onSelect: () => duplicateVisit(visit) });
		if (!visit.completed_at) {
			items.push({
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				onSelect: () => (deleteTarget = visit)
			});
		}
		return items;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Scheduled visits" icon={calendarIcon} level={2}>
	{#snippet actions()}
		{#if canSchedule}
			{#if isRecurringScheduled}
				<Button size="small" variant="tertiary" onclick={() => (editingAll = true)}>
					Edit all visits
				</Button>
			{/if}
			<Button size="small" variant="tertiary" onclick={() => (creating = true)} loading={addSaving}>
				Add visits
			</Button>
		{/if}
	{/snippet}

	{#if addError}<p class="job-visits-section__error" role="alert">{addError}</p>{/if}

	{#if visits.length === 0}
		<EmptyState
			icon={calendarIcon}
			title="No visits yet"
			description={canSchedule
				? 'Add the days your team will be on site. You can pick several at once.'
				: 'This job has no visits scheduled.'}
		>
			{#snippet action()}
				{#if canSchedule}
					<Button variant="secondary" onclick={() => (creating = true)}>Add visits</Button>
				{/if}
			{/snippet}
		</EmptyState>
	{:else}
		{#if canSchedule && selectedIds.size > 0}
			<div class="job-visits-section__bulk">
				<span class="job-visits-section__bulk-count">
					{selectedIds.size}
					{selectedIds.size === 1 ? 'visit' : 'visits'} selected
				</span>
				<label class="job-visits-section__bulk-field" for="job-visits-move-days">
					Move by (days)
					<input
						id="job-visits-move-days"
						class="job-visits-section__bulk-input"
						type="number"
						bind:value={moveDays}
					/>
				</label>
				<Button size="small" onclick={() => void moveSelected()} loading={moving}>Move</Button>
				<Button size="small" variant="tertiary" onclick={clearSelection}>Clear</Button>
			</div>
		{/if}

		<ul class="job-visits-section__list">
			{#each visits as visit (visit.id)}
				<li class="job-visits-section__item" onpointerenter={warmTeam} onfocusin={warmTeam}>
					{#if canSchedule && canSelect(visit)}
						<input
							type="checkbox"
							class="job-visits-section__checkbox"
							aria-label={`Select ${visit.title?.trim() || jobTitle.trim() || 'this visit'} for a bulk move`}
							checked={selectedIds.has(visit.id)}
							onchange={(event) => toggleSelect(visit.id, event.currentTarget.checked)}
						/>
					{:else}
						<span class="job-visits-section__checkbox-spacer" aria-hidden="true"></span>
					{/if}

					<span class="job-visits-section__icon" aria-hidden="true">{@html calendarIcon}</span>

					<div class="job-visits-section__body">
						<p class="job-visits-section__when">
							{visit.title ? `${visit.title} · ` : ''}{visitWhen(visit)}
						</p>
						{#if visit.instructions}
							<p class="job-visits-section__note">{visit.instructions}</p>
						{/if}
					</div>

					<div class="job-visits-section__meta">
						{#if visit.completed_at}
							<Badge size="small" status="success">Completed</Badge>
						{/if}
						{#if visit.assignee_ids.length > 0}
							<span class="job-visits-section__assignees">
								<span aria-hidden="true">{@html usersIcon}</span>
								{visit.assignee_ids.length}
							</span>
						{/if}
					</div>

					{#if canSchedule}
						<DropdownMenu items={rowMenuItems(visit)} triggerLabel="Actions for this visit" />
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</SectionBlock>

<CreateVisitsDialog open={creating} onClose={() => (creating = false)} onCreate={handleCreate} />

<JobVisitDialog
	open={editVisit !== null}
	visit={editVisit}
	{jobTitle}
	{locale}
	isRecurring={isRecurringScheduled}
	saving={editSaving}
	error={editError}
	onSave={saveEdit}
	onSaveFuture={saveEditThenFuture}
	onClose={() => (editVisit = null)}
/>

<EditAllVisitsDialog
	open={editingAll}
	{visits}
	currentRule={recurrence}
	{locale}
	saving={rescheduleSaving}
	error={rescheduleError}
	onSave={(rule) => void saveReschedule(rule)}
	onClose={() => (editingAll = false)}
/>

<ApplyToFutureDialog
	open={applyTarget !== null}
	visitLabel={applyTarget?.label ?? 'this visit'}
	laterCount={applyLaterCount}
	saving={applySaving}
	error={applyError}
	onApply={(fields) => void confirmApplyFuture(fields)}
	onClose={() => (applyTarget = null)}
/>

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this visit?"
	tone="critical"
	destructive
	confirmLabel="Delete visit"
	loading={deleting}
	onConfirm={() => void confirmDelete()}
	onClose={() => (deleteTarget = null)}
>
	This removes the visit from the job. This cannot be undone.
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-visits-section {
		&__error {
			margin: 0 0 var(--space-small);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__bulk {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			gap: var(--space-small);
			margin-bottom: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__bulk-count {
			flex: 1 1 auto;
			align-self: center;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__bulk-field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__bulk-input {
			width: 96px;
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			background: var(--color-surface);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: flex-start;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__checkbox {
			flex: 0 0 auto;
			margin-top: 2px;
			width: 16px;
			height: 16px;
		}

		&__checkbox-spacer {
			flex: 0 0 16px;
		}

		&__icon {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-icon);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		&__body {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__when {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__note {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			white-space: pre-wrap;
		}

		&__meta {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-small);
		}

		&__assignees {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
