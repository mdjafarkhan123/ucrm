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
	import FinalVisitDialog from '$lib/components/jobs/FinalVisitDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import type { JobType } from '$lib/jobs/statuses';
	import {
		addJobVisits,
		applyVisitToFuture,
		closeJob,
		completeJobVisit,
		deleteJobVisit,
		jobCountsKey,
		jobDetailKey,
		jobEventsKey,
		rescheduleJobVisits,
		uncompleteJobVisit,
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
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import circleXIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import calendarPlusIcon from '@tabler/icons/outline/calendar-plus.svg?raw';
	import repeatIcon from '@tabler/icons/outline/repeat.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// The persisted visits manager for a job's detail page — the same "child record with its own save" shape
	// as a client's property: every action here writes for itself and reports its own toast, so the page's
	// title/instructions draft never has to know visits exist. The card mirrors Jobber's grouped Visits card:
	// To be scheduled / Upcoming / Past, with only the next three Upcoming shown until "Show all".
	let {
		jobId,
		visits,
		jobTitle = '',
		locale = 'en-US',
		canSchedule,
		canComplete,
		canClose,
		jobStatus,
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
		canComplete: boolean;
		canClose: boolean;
		jobStatus: 'active' | 'closed';
		jobType: JobType;
		isAsNeeded: boolean;
		// The job's repeat rule, present only for a recurring scheduled job. "Edit Schedule" opens on it.
		recurrence: JobRecurrenceInput | null;
		// The job's own lock token — the reschedule command guards on it, exactly like saving the details does.
		jobRevision: number;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// A closed job's visits are frozen (complete_job_visit and update_job_visit both refuse on the database
	// side); scheduling and completing only ever show as available on an active job, so a click never has to
	// discover that the hard way.
	const scheduleAllowed = $derived(canSchedule && jobStatus === 'active');
	const completeAllowed = $derived(canComplete && jobStatus === 'active');

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

	// --- Grouping -----------------------------------------------------------------------------------------

	// Local calendar day as YYYY-MM-DD, so "past" is a plain string compare against a visit's date-only value.
	const todayStr = $derived.by(() => {
		const now = new Date();
		const y = now.getFullYear();
		const m = String(now.getMonth() + 1).padStart(2, '0');
		const d = String(now.getDate()).padStart(2, '0');
		return `${y}-${m}-${d}`;
	});

	// A visit is either done (Past), or not yet done with a day (Upcoming, soonest first — an overdue one
	// sorts to the top and shows an Overdue flag), or not yet done with no day at all (To be scheduled).
	const toBeScheduled = $derived(visits.filter((v) => v.visit_date === null && !v.completed_at));
	const upcoming = $derived(
		visits
			.filter((v) => v.visit_date !== null && !v.completed_at)
			.sort((a, b) => (a.visit_date! < b.visit_date! ? -1 : a.visit_date! > b.visit_date! ? 1 : 0))
	);
	const past = $derived(
		visits
			.filter((v) => v.completed_at !== null)
			.sort((a, b) => ((b.visit_date ?? '') < (a.visit_date ?? '') ? 1 : -1))
	);

	// Only the next three Upcoming show until the user asks for the rest; Past is collapsed until opened.
	let showAllUpcoming = $state(false);
	let showPast = $state(false);
	const upcomingVisible = $derived(showAllUpcoming ? upcoming : upcoming.slice(0, 3));
	const upcomingHidden = $derived(upcoming.length - upcomingVisible.length);

	function isOverdue(visit: JobVisit) {
		return !visit.completed_at && visit.visit_date !== null && visit.visit_date < todayStr;
	}

	// --- Recurrence summary -------------------------------------------------------------------------------

	const WEEKDAY_NAMES = [
		'Sunday',
		'Monday',
		'Tuesday',
		'Wednesday',
		'Thursday',
		'Friday',
		'Saturday'
	];
	const ORDINAL_NAMES: Record<number, string> = {
		1: 'first',
		2: 'second',
		3: 'third',
		4: 'fourth',
		5: 'last'
	};

	// A plain-English summary of the repeat rule, the way Jobber shows one ("Weekly on Mondays"). Read off the
	// stored rule; the concrete visits carry the real count and range below it.
	function describeRecurrence(rule: JobRecurrenceInput | null): string {
		if (!rule) return '';
		const n = rule.interval_count ?? 1;
		switch (rule.frequency) {
			case 'daily':
				return n === 1 ? 'Daily' : `Every ${n} days`;
			case 'weekly': {
				const source = rule.weekdays?.length
					? rule.weekdays
					: [new Date(`${rule.start_date}T00:00`).getDay()];
				const list = source
					.slice()
					.sort((a, b) => a - b)
					.map((d) => WEEKDAY_NAMES[d])
					.join(', ');
				return n === 1 ? `Weekly on ${list}` : `Every ${n} weeks on ${list}`;
			}
			case 'monthly': {
				const prefix = n === 1 ? 'Monthly' : `Every ${n} months`;
				if (rule.monthly_mode === 'last_day') return `${prefix} on the last day`;
				if (
					rule.monthly_mode === 'day_of_week' &&
					rule.ordinal_week != null &&
					rule.ordinal_weekday != null
				) {
					return `${prefix} on the ${ORDINAL_NAMES[rule.ordinal_week] ?? ''} ${WEEKDAY_NAMES[rule.ordinal_weekday]}`;
				}
				if (rule.monthly_mode === 'day_of_month' && rule.month_day != null) {
					return `${prefix} on day ${rule.month_day}`;
				}
				return prefix;
			}
			case 'yearly':
				return n === 1 ? 'Yearly' : `Every ${n} years`;
			default:
				return '';
		}
	}

	const recurrenceSummary = $derived(
		isRecurringScheduled ? describeRecurrence(recurrence) : ''
	);
	// Count and range come from the real visit rows, not the rule, so they match what is on screen exactly.
	const seriesDates = $derived(
		visits
			.filter((v) => v.visit_date !== null)
			.map((v) => v.visit_date!)
			.sort()
	);
	const seriesFirst = $derived(seriesDates[0] ?? null);
	const seriesLast = $derived(seriesDates[seriesDates.length - 1] ?? null);

	// --- Formatting ---------------------------------------------------------------------------------------

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	const timeFormat = $derived(
		new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' })
	);

	function formatDay(value: string) {
		return dateFormat.format(new Date(`${value}T00:00`));
	}
	function formatTime(value: string) {
		return timeFormat.format(new Date(`2000-01-01T${value}`));
	}

	function visitWhen(visit: JobVisit) {
		if (!visit.visit_date) return 'No date yet';
		const day = formatDay(visit.visit_date);
		if (!visit.start_time) return `${day} · Anytime`;
		const start = formatTime(visit.start_time);
		if (visit.end_time) return `${day} · ${start}–${formatTime(visit.end_time)}`;
		return `${day} · ${start}`;
	}

	function completedWhen(visit: JobVisit) {
		if (!visit.completed_at) return '';
		return `Completed ${dateFormat.format(new Date(visit.completed_at))}`;
	}

	const seriesRange = $derived(
		seriesFirst
			? seriesFirst === seriesLast
				? formatDay(seriesFirst)
				: `${formatDay(seriesFirst)} – ${formatDay(seriesLast!)}`
			: ''
	);

	// --- Add visits ----------------------------------------------------------------------------------------

	let creating = $state(false);
	let addSaving = $state(false);
	let addError = $state('');
	// "Add one visit" opens the day-picker in single mode; "Add multiple visits" keeps the many-days mode.
	let createMode = $state<'single' | 'multiple'>('multiple');

	function openAdd(mode: 'single' | 'multiple') {
		createSource = 'manual';
		createMode = mode;
		creating = true;
	}

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
		const source = createSource;
		createSource = 'manual';
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
						source
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
					source
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

	// --- Edit the schedule (recurring) -----------------------------------------------------------------------

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

	function rowMenuItems(visit: JobVisit) {
		const items: {
			label: string;
			icon?: string;
			onSelect: () => void;
			destructive?: boolean;
		}[] = [];
		if (completeAllowed) {
			items.push(
				visit.completed_at
					? {
							label: 'Mark Incomplete',
							icon: circleXIcon,
							onSelect: () => void handleUncomplete(visit)
						}
					: {
							label: 'Mark Complete',
							icon: circleCheckIcon,
							onSelect: () => void handleComplete(visit)
						}
			);
		}
		if (!visit.completed_at && scheduleAllowed) {
			items.push({ label: 'Edit', icon: pencilIcon, onSelect: () => (editVisit = visit) });
		}
		if (scheduleAllowed) {
			items.push({ label: 'Duplicate', icon: copyIcon, onSelect: () => duplicateVisit(visit) });
		}
		if (!visit.completed_at && scheduleAllowed) {
			items.push({
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				onSelect: () => (deleteTarget = visit)
			});
		}
		return items;
	}

	// --- Complete / uncomplete a visit ------------------------------------------------------------------------

	let finalVisitOpen = $state(false);
	let closingFinal = $state(false);
	// "Add a return visit" from the final-visit dialog opens the same create-visits flow, tagged as a return
	// trip rather than an ordinary manual add so the history reads truthfully.
	let createSource = $state<'manual' | 'return'>('manual');

	async function handleComplete(visit: JobVisit) {
		try {
			const result = await completeJobVisit(jobId, visit.id);
			await refreshAll();
			toast.success('Visit marked complete');
			if (result.final_visit) finalVisitOpen = true;
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'That visit could not be marked complete.');
		}
	}

	async function handleUncomplete(visit: JobVisit) {
		try {
			await uncompleteJobVisit(jobId, visit.id);
			await refreshAll();
			toast.success('Visit marked incomplete');
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'That visit could not be reopened.');
		}
	}

	async function finishJob() {
		closingFinal = true;
		try {
			await closeJob(jobId, jobRevision);
			finalVisitOpen = false;
			await refreshAll();
			toast.success('Job finished');
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'That job could not be closed.');
		} finally {
			closingFinal = false;
		}
	}

	function openReturnVisitFromFinal() {
		finalVisitOpen = false;
		createSource = 'return';
		createMode = 'single';
		creating = true;
	}

	const addMenuItems = $derived([
		{ label: 'Add one visit', icon: plusIcon, onSelect: () => openAdd('single') },
		{ label: 'Add multiple visits', icon: calendarPlusIcon, onSelect: () => openAdd('multiple') }
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet visitRow(visit: JobVisit)}
	<li class="job-visits-section__item" onpointerenter={warmTeam} onfocusin={warmTeam}>
		<span class="job-visits-section__icon" aria-hidden="true">{@html calendarIcon}</span>

		<div class="job-visits-section__body">
			<p class="job-visits-section__when">
				{visit.title ? `${visit.title} · ` : ''}{visitWhen(visit)}
			</p>
			{#if visit.completed_at}
				<p class="job-visits-section__sub">{completedWhen(visit)}</p>
			{/if}
			{#if visit.instructions}
				<p class="job-visits-section__note">{visit.instructions}</p>
			{/if}
		</div>

		<div class="job-visits-section__meta">
			{#if visit.completed_at}
				<Badge size="small" status="success">Completed</Badge>
			{:else if isOverdue(visit)}
				<Badge size="small" status="warning">Overdue</Badge>
			{/if}
			{#if visit.assignee_ids.length > 0}
				<span class="job-visits-section__assignees">
					<span aria-hidden="true">{@html usersIcon}</span>
					{visit.assignee_ids.length}
				</span>
			{/if}
		</div>

		{#if scheduleAllowed || completeAllowed}
			<DropdownMenu items={rowMenuItems(visit)} triggerLabel="Actions for this visit" />
		{/if}
	</li>
{/snippet}

<SectionBlock title="Visits" icon={calendarIcon} level={2}>
	{#snippet actions()}
		{#if scheduleAllowed}
			{#if isRecurringScheduled}
				<Button size="small" variant="tertiary" onclick={() => (editingAll = true)}>
					Edit Schedule
				</Button>
			{/if}
			<DropdownMenu
				items={addMenuItems}
				triggerLabel="Add visits"
				triggerClass="job-visits-section__add-trigger"
			>
				{#snippet trigger()}
					<span class="job-visits-section__add-icon" aria-hidden="true">{@html plusIcon}</span>
					Add visits
					<span class="job-visits-section__add-caret" aria-hidden="true">{@html chevronDownIcon}</span>
				{/snippet}
			</DropdownMenu>
		{/if}
	{/snippet}

	{#if addError}<p class="job-visits-section__error" role="alert">{addError}</p>{/if}

	{#if isRecurringScheduled && recurrenceSummary}
		<div class="job-visits-section__recurrence">
			<span class="job-visits-section__recurrence-icon" aria-hidden="true">{@html repeatIcon}</span>
			<span class="job-visits-section__recurrence-text">
				<span class="job-visits-section__recurrence-summary">{recurrenceSummary}</span>
				<span class="job-visits-section__recurrence-detail">
					{visits.length}
					{visits.length === 1 ? 'visit' : 'visits'}{seriesRange ? ` · ${seriesRange}` : ''}
				</span>
			</span>
		</div>
	{/if}

	{#if visits.length === 0}
		<EmptyState
			icon={calendarIcon}
			title={isAsNeeded ? 'Dispatched as needed' : 'No visits yet'}
			description={isAsNeeded
				? 'This job has no set schedule. Add a visit whenever work comes up.'
				: scheduleAllowed
					? 'Add the days your team will be on site. You can pick several at once.'
					: 'This job has no visits scheduled.'}
		>
			{#snippet action()}
				{#if scheduleAllowed}
					<Button variant="secondary" onclick={() => openAdd(isAsNeeded ? 'single' : 'multiple')}>
						{isAsNeeded ? 'Add a visit' : 'Add visits'}
					</Button>
				{/if}
			{/snippet}
		</EmptyState>
	{:else}
		<div class="job-visits-section__groups">
			{#if toBeScheduled.length > 0}
				<div class="job-visits-section__group">
					<p class="job-visits-section__group-title">
						To be scheduled <span class="job-visits-section__group-count"
							>{toBeScheduled.length}</span
						>
					</p>
					<ul class="job-visits-section__list">
						{#each toBeScheduled as visit (visit.id)}
							{@render visitRow(visit)}
						{/each}
					</ul>
				</div>
			{/if}

			{#if upcoming.length > 0}
				<div class="job-visits-section__group">
					<p class="job-visits-section__group-title">
						Upcoming <span class="job-visits-section__group-count">{upcoming.length}</span>
					</p>
					<ul class="job-visits-section__list">
						{#each upcomingVisible as visit (visit.id)}
							{@render visitRow(visit)}
						{/each}
					</ul>
					{#if upcomingHidden > 0}
						<button
							type="button"
							class="job-visits-section__more"
							onclick={() => (showAllUpcoming = true)}
						>
							Show all {upcoming.length} upcoming visits
						</button>
					{:else if showAllUpcoming && upcoming.length > 3}
						<button
							type="button"
							class="job-visits-section__more"
							onclick={() => (showAllUpcoming = false)}
						>
							Show fewer
						</button>
					{/if}
				</div>
			{/if}

			{#if past.length > 0}
				<div class="job-visits-section__group">
					<button
						type="button"
						class="job-visits-section__group-toggle"
						aria-expanded={showPast}
						onclick={() => (showPast = !showPast)}
					>
						<span
							class="job-visits-section__group-caret"
							class:job-visits-section__group-caret--open={showPast}
							aria-hidden="true">{@html chevronDownIcon}</span
						>
						Past <span class="job-visits-section__group-count">{past.length}</span>
					</button>
					{#if showPast}
						<ul class="job-visits-section__list">
							{#each past as visit (visit.id)}
								{@render visitRow(visit)}
							{/each}
						</ul>
					{/if}
				</div>
			{/if}
		</div>
	{/if}
</SectionBlock>

<CreateVisitsDialog
	open={creating}
	mode={createMode}
	onClose={() => {
		creating = false;
		createSource = 'manual';
	}}
	onCreate={handleCreate}
/>

<FinalVisitDialog
	open={finalVisitOpen}
	{canClose}
	closing={closingFinal}
	onFinish={() => void finishJob()}
	onAddReturnVisit={openReturnVisitFromFinal}
	onKeepOpen={() => (finalVisitOpen = false)}
/>

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

		&__recurrence {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-bottom: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__recurrence-icon {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-icon--secondary);

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}

		&__recurrence-text {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-smaller) var(--space-small);
		}

		&__recurrence-summary {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__recurrence-detail {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__groups {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
		}

		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__group-title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.03em;
		}

		&__group-count {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			min-width: 20px;
			height: 20px;
			padding: 0 var(--space-smaller);
			border-radius: var(--radius-large);
			color: var(--color-heading);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0;
		}

		&__group-toggle {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			width: fit-content;
			padding: 0;
			border: 0;
			background: transparent;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.03em;
			cursor: pointer;

			&:hover {
				color: var(--color-heading);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
				border-radius: var(--radius-small);
			}
		}

		&__group-caret {
			display: inline-flex;
			color: var(--color-icon--secondary);
			transition: transform var(--timing-quick);

			&--open {
				transform: rotate(180deg);
			}

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__more {
			align-self: flex-start;
			padding: var(--space-smaller) 0;
			border: 0;
			background: transparent;
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
				border-radius: var(--radius-small);
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

		&__sub {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
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

	:global(.job-visits-section__add-trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smaller) var(--space-small);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-interactive);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;
		transition: background-color var(--timing-base) ease-out;

		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.job-visits-section__add-icon svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	:global(.job-visits-section__add-caret svg) {
		display: block;
		width: 14px;
		height: 14px;
	}
</style>
