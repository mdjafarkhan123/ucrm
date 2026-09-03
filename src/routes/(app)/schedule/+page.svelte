<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import type { ResolvedPathname } from '$app/types';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Popover from '$lib/components/ui/Popover.svelte';
	import ScheduleControls from '$lib/components/schedule/ScheduleControls.svelte';
	import ScheduleDay from '$lib/components/schedule/ScheduleDay.svelte';
	import ScheduleMonth from '$lib/components/schedule/ScheduleMonth.svelte';
	import ScheduleWeek from '$lib/components/schedule/ScheduleWeek.svelte';
	import VisitPreview from '$lib/components/schedule/VisitPreview.svelte';
	import AssessmentPreview from '$lib/components/schedule/AssessmentPreview.svelte';
	import MoveConfirm from '$lib/components/schedule/MoveConfirm.svelte';
	import ScheduleUnscheduledDrawer from '$lib/components/schedule/ScheduleUnscheduledDrawer.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import JobVisitDialog from '$lib/components/jobs/JobVisitDialog.svelte';
	import ApplyToFutureDialog from '$lib/components/jobs/ApplyToFutureDialog.svelte';
	import FinalVisitDialog from '$lib/components/jobs/FinalVisitDialog.svelte';
	import CreateVisitsDialog from '$lib/components/jobs/CreateVisitsDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { workingWeek } from '$lib/schedule/hours';
	import { formatCalendarDay, visitClientLabel, visitWorkLabel } from '$lib/schedule/labels';
	import {
		describeChange,
		futureScopeFields,
		proposeMove,
		type DropTarget,
		type NewVisitDraft,
		type ScheduleProposal
	} from '$lib/schedule/drag';
	import { startPointerDrag } from '$lib/schedule/pointer-drag';
	import { scheduleWarnings } from '$lib/schedule/conflicts';
	import {
		addJobVisits,
		applyVisitToFuture,
		closeJob,
		completeJobVisit,
		createJob,
		fetchJob,
		jobCountsKey,
		jobDetailKey,
		jobEventsKey,
		uncompleteJobVisit,
		updateJobVisit,
		type AddVisitInput,
		type CreateJobPayload,
		type JobVisitInput,
		type JobWriteError,
		type UpdateVisitInput
	} from '$lib/jobs/api';
	import { stageJobCreateSeed, type JobCreateSeed } from '$lib/jobs/createDraft';
	import { stageAssessmentSeed, type AssessmentCreateSeed } from '$lib/requests/assessmentSeed';
	import ScheduleJobCreate from '$lib/components/schedule/ScheduleJobCreate.svelte';
	import {
		fetchScheduleContext,
		fetchScheduleUnscheduled,
		fetchScheduleWindow,
		scheduleContextKey,
		scheduleUnscheduledKey,
		scheduleWindowKey
	} from '$lib/schedule/api';
	import {
		reanchorScheduleDate,
		readScheduleFilters,
		scheduleFilterParams,
		scheduleWindow,
		shiftScheduleDate,
		type ScheduleEmployeeFilter,
		type ScheduleFilters
	} from '$lib/schedule/filters';
	import { filterVisits, indexEmployees } from '$lib/schedule/grouping';
	import {
		assessmentToItem,
		visitToItem,
		type AssessmentItem,
		type VisitItem
	} from '$lib/schedule/items';
	import { readScheduleZoom, writeScheduleZoom, type ScheduleZoom } from '$lib/schedule/density';
	import { calendarDay, clockMinutesInZone } from '$lib/time/calendar-day';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import type { ScheduleVisit, UnscheduledVisit } from '$lib/schedule/api';
	import type { ScheduleView } from '$lib/schedule/statuses';

	// The calendar's operating facts. They almost never change, so this is asked once and reused while the
	// person clicks through the weeks.
	const contextQuery = createQuery(() => ({
		queryKey: scheduleContextKey,
		queryFn: fetchScheduleContext,
		staleTime: 10 * 60 * 1000
	}));

	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 5 * 60 * 1000
	}));

	// Every day the calendar names is the contractor's own day, not the browser's. Until the timezone has
	// arrived there is no honest answer, so the workspace waits rather than guessing with the device clock.
	const timezone = $derived(contextQuery.data?.timezone ?? null);

	// The clock the calendar reads. It ticks so the current-time line moves and so a calendar left open
	// overnight rolls onto the new day instead of insisting yesterday is still today.
	let clock = $state(new Date());
	$effect(() => {
		const tick = setInterval(() => (clock = new Date()), 60_000);
		return () => clearInterval(tick);
	});

	const today = $derived(timezone ? calendarDay(clock, timezone) : null);
	const nowMinutes = $derived(timezone ? clockMinutesInZone(clock, timezone) : null);

	// Which hours of each weekday are working hours. Null when the business has not confirmed a weekly
	// pattern, and the grid then shades nothing rather than inventing nine to five.
	const workingHours = $derived(contextQuery.data ? workingWeek(contextQuery.data) : null);

	// The URL is the calendar's memory: the date, the view and both filters live there and nowhere else.
	// Today is the fallback anchor, so a plain /schedule link always opens on the current week.
	const filters = $derived<ScheduleFilters | null>(
		today ? readScheduleFilters(page.url.searchParams, today) : null
	);
	const activeWindow = $derived(filters ? scheduleWindow(filters.date, filters.view) : null);

	const windowQuery = createQuery(() => ({
		queryKey: activeWindow
			? scheduleWindowKey(activeWindow)
			: (['schedule', 'window', 'pending'] as const),
		queryFn: () => fetchScheduleWindow(activeWindow!),
		enabled: activeWindow !== null,
		staleTime: 30_000
	}));

	// --- The Unscheduled backlog drawer ------------------------------------------------------------------

	// The backlog is revealed content, not part of the calendar the page opens on, so its read stays off until
	// the person reaches for it: hovering the toggle warms it, opening it keeps it warm. Its search and
	// employee filter live here so they survive the drawer being closed and reopened.
	let unscheduledOpen = $state(false);
	let unscheduledWarm = $state(false);
	let backlogQuery = $state('');
	let backlogEmployee = $state<ScheduleEmployeeFilter>('all');
	let unscheduleDropZone = $state<HTMLElement | null>(null);

	const unscheduledQuery = createQuery(() => ({
		queryKey: scheduleUnscheduledKey,
		queryFn: fetchScheduleUnscheduled,
		enabled: unscheduledOpen || unscheduledWarm,
		staleTime: 30_000
	}));

	// The toggle's count. Null until the read has happened, so the badge stays blank rather than claiming zero
	// before it knows.
	const unscheduledCount = $derived(unscheduledQuery.data?.visits.length ?? null);

	function applyFilters(next: ScheduleFilters) {
		if (!today) return;
		// The preview belongs to the card it was opened from, and that card is about to be gone.
		closePreview();
		// The destination is always this page; only its query changes. The cast says what the concatenation
		// cannot: a resolved route with its own query on the end is still that resolved route.
		const query = scheduleFilterParams(next, today).toString();
		const route: string = resolve('/(app)/schedule');
		const destination = (query ? `${route}?${query}` : route) as ResolvedPathname;
		// Each change is its own history entry, so Back steps through the calendar the way it steps through
		// pages, and the workspace does not jump to the top.
		void goto(destination, { keepFocus: true, noScroll: true });
	}

	function changeFilters(patch: Partial<ScheduleFilters>) {
		if (!filters) return;
		const next = { ...filters, ...patch };
		// Changing the view keeps the closest equivalent date, as the behaviour contract requires.
		if (patch.view && patch.view !== filters.view) {
			next.date = reanchorScheduleDate(filters.date, filters.view, patch.view);
		}
		applyFilters(next);
	}

	function step(direction: -1 | 1) {
		if (!filters) return;
		applyFilters({ ...filters, date: shiftScheduleDate(filters.date, filters.view, direction) });
	}

	function goToToday() {
		if (!filters || !today) return;
		applyFilters({ ...filters, date: today });
	}

	// How roomy the reader wants the time grid. A per-person viewing preference kept in the browser, seeded
	// from their last choice; it never enters the URL or the window read.
	let zoom = $state<ScheduleZoom>(readScheduleZoom());

	function changeZoom(next: ScheduleZoom) {
		zoom = next;
		writeScheduleZoom(next);
	}

	const employeesById = $derived(indexEmployees(teamQuery.data ?? []));

	// The calendar draws visits and Request-owned assessments together (Version 1.1). Assessments arrive as raw
	// instants, so they are converted to the organization's own day and clock here, where the timezone is known,
	// then flow through the same filter, grouping and layout the visits do. Nothing merges until the timezone
	// has arrived, because an assessment placed with the browser's clock would land on the wrong day.
	const scheduleItems = $derived.by(() => {
		const zone = timezone;
		const win = activeWindow;
		const visits = (windowQuery.data?.visits ?? []).map(visitToItem);
		if (!zone || !win) return visits;
		// The window read over-fetches assessments a day past each edge, because their instants are bounded in
		// UTC while the window is a range of org-timezone days. Now that each one has been placed on its real
		// day, the ones that fell outside the window are trimmed -- otherwise the Day board, which buckets by
		// employee rather than by day, would draw a neighbouring day's assessment in today's rows.
		const assessments = (windowQuery.data?.assessments ?? [])
			.map((assessment) => assessmentToItem(assessment, zone))
			.filter(
				(item) =>
					item.visit_date !== null && item.visit_date >= win.from && item.visit_date <= win.to
			);
		return [...visits, ...assessments];
	});

	const visibleItems = $derived(
		filters && today ? filterVisits(scheduleItems, filters, today) : []
	);

	const hasFilter = $derived(
		filters !== null && (filters.employee !== 'all' || filters.status !== 'all')
	);

	// Everything in this window matched a filter away. The calendar itself stays on screen -- an empty week
	// with a note beats replacing the whole workspace with an empty state.
	const filteredEmpty = $derived(
		hasFilter && visibleItems.length === 0 && scheduleItems.length > 0
	);

	// One preview for the whole calendar, pointed at whichever card is selected. The card is remembered by
	// id rather than by value, so a background refetch updates what the preview says instead of freezing it.
	// A visit and an assessment are different objects with different previews, so each has its own selection;
	// only one is ever set, and the grids highlight whichever id is selected.
	let selectedVisitId = $state<string | null>(null);
	let selectedAssessmentId = $state<string | null>(null);
	let previewAnchor = $state<HTMLElement | null>(null);
	// The visit preview can be opened from a calendar card or from a backlog card, so it looks in both places.
	const selectedVisit = $derived(
		visibleItems.find(
			(item): item is VisitItem => item.kind === 'visit' && item.id === selectedVisitId
		) ??
			unscheduledQuery.data?.visits.find((visit) => visit.id === selectedVisitId) ??
			null
	);
	const selectedAssessment = $derived(
		visibleItems.find(
			(item): item is AssessmentItem =>
				item.kind === 'assessment' && item.id === selectedAssessmentId
		) ?? null
	);
	const selectedItemId = $derived(selectedVisitId ?? selectedAssessmentId);

	function openPreview(visit: ScheduleVisit, element: HTMLElement) {
		selectedAssessmentId = null;
		selectedVisitId = visit.id;
		previewAnchor = element;
	}

	function openAssessmentPreview(assessment: AssessmentItem, element: HTMLElement) {
		selectedVisitId = null;
		selectedAssessmentId = assessment.id;
		previewAnchor = element;
	}

	function closePreview() {
		selectedVisitId = null;
		selectedAssessmentId = null;
		previewAnchor = null;
	}

	// --- Moving, resizing and reassigning ----------------------------------------------------------------

	// The calendar proposes; the Jobs commands write. Nothing on this page invents a schedule rule of its
	// own: a drag becomes a proposal, the person confirms it, and the same `update_job_visit` and
	// `apply_visit_to_future` the Job page uses do the work, so both screens behave identically.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const canSchedule = $derived(contextQuery.data?.can_schedule ?? false);
	// Empty-space creation starts a Job, so it follows Job-create authority, not the schedule authority that
	// governs moving existing visits.
	const canCreate = $derived(contextQuery.data?.can_create_job ?? false);
	// Completion is its own Jobs-owned authority. `canComplete` shows the complete/uncomplete control at all;
	// `canClose` decides whether the final-visit dialog offers "Finish job".
	const canComplete = $derived(contextQuery.data?.can_complete ?? false);
	const canClose = $derived(contextQuery.data?.can_close ?? false);

	/** A drag that has landed and is waiting for the person to press Save. */
	let pending = $state<{
		visit: ScheduleVisit;
		proposal: ScheduleProposal;
		anchor: HTMLElement;
	} | null>(null);
	let moveSaving = $state(false);
	let moveError = $state('');

	/** The visit whose full Jobs edit dialog is open -- the keyboard and button path to the same changes. */
	let rescheduleVisitId = $state<string | null>(null);
	let rescheduleSaving = $state(false);
	let rescheduleError = $state('');

	/** The dated visit being sent back to the backlog, waiting on the explicit confirmation. */
	let unscheduleVisitId = $state<string | null>(null);
	let unscheduleSaving = $state(false);
	let unscheduleError = $state('');

	// One job is read at a time: whichever visit is being changed. It carries the two things a calendar card
	// does not -- whether the job repeats, and the visit's own title and instructions, which the update
	// command rewrites wholesale and must therefore be given back unchanged.
	const workingVisit = $derived.by(() => {
		if (pending) return pending.visit;
		const id = rescheduleVisitId ?? unscheduleVisitId;
		if (!id) return null;
		// A drag-move or reschedule works on a dated window visit; the drawer's Schedule button works on a
		// backlog visit. Both need the job read, so both lists are searched.
		return (
			windowQuery.data?.visits.find((visit) => visit.id === id) ??
			unscheduledQuery.data?.visits.find((visit) => visit.id === id) ??
			null
		);
	});
	const workingJobId = $derived(workingVisit?.job_id ?? null);

	const jobQuery = createQuery(() => ({
		queryKey: workingJobId ? jobDetailKey(workingJobId) : (['jobs', 'detail', 'idle'] as const),
		queryFn: () => fetchJob(workingJobId!),
		enabled: workingJobId !== null,
		// Never held. A cached job would hand back the visit's old times, its old instructions and an old
		// lock token -- and the update command replaces the whole visit, so writing from a stale copy would
		// quietly undo somebody else's edit. Both surfaces wait for this read before they will save.
		staleTime: 0,
		refetchOnMount: 'always'
	}));

	/** The visit as the Job page knows it: with its title, instructions and its own lock token. */
	const workingJobVisit = $derived(
		workingVisit ? (jobQuery.data?.visits.find((v) => v.id === workingVisit.id) ?? null) : null
	);

	const pendingChange = $derived(pending ? describeChange(pending.visit, pending.proposal) : null);

	// Warnings read every visit in the window, not the filtered ones. Hiding a clash because a filter is on
	// would be the calendar lying by omission.
	const pendingWarnings = $derived(
		pending
			? scheduleWarnings({
					visitId: pending.visit.id,
					proposal: pending.proposal,
					visits: windowQuery.data?.visits ?? [],
					workingWeek: workingHours
				})
			: []
	);

	function proposeChange(visit: ScheduleVisit, proposal: ScheduleProposal, anchor: HTMLElement) {
		closePreview();
		moveError = '';
		pending = { visit, proposal, anchor };
	}

	function cancelMove() {
		pending = null;
		moveError = '';
	}

	function openReschedule(visit: ScheduleVisit) {
		closePreview();
		pending = null;
		rescheduleError = '';
		rescheduleVisitId = visit.id;
	}

	function closeReschedule() {
		rescheduleVisitId = null;
		rescheduleError = '';
	}

	// --- Placing a backlog visit by dragging it onto the calendar ----------------------------------------

	// The active time grid, whichever it is. Month has no time axis to drop onto, so it exposes no external
	// drag and stays null; the drawer's Schedule button is the placement path there.
	let weekGrid = $state<ScheduleWeek | null>(null);
	let dayGrid = $state<ScheduleDay | null>(null);
	const activeGrid = $derived<ScheduleWeek | ScheduleDay | null>(weekGrid ?? dayGrid);

	/** The backlog card being dragged out, drawn lifted in the drawer while it travels. */
	let placingVisitId = $state<string | null>(null);
	/** A chip that follows the pointer so the person can see what they are carrying onto the grid. */
	let dragGhost = $state<{ x: number; y: number; label: string } | null>(null);

	// A backlog card was picked up by its handle. Nothing is written by the drag: it only probes the grid for
	// where the pointer is and, on release over a real slot, proposes the same move an internal drag would.
	function pickUpFromBacklog(event: PointerEvent, visit: UnscheduledVisit) {
		const grid = activeGrid;
		if (!grid) return;
		startPointerDrag(event, {
			onStart: () => {
				placingVisitId = visit.id;
			},
			onMove: (moved) => {
				grid.probeExternal(visit, moved);
				dragGhost = { x: moved.clientX, y: moved.clientY, label: visitWorkLabel(visit) };
			},
			onDrop: (dropped) => {
				const landing = grid.probeExternal(visit, dropped);
				grid.clearExternal();
				dragGhost = null;
				placingVisitId = null;
				if (landing) proposeChange(visit, proposeMove(visit, landing.target), landing.anchor);
			},
			onCancel: () => {
				grid.clearExternal();
				dragGhost = null;
				placingVisitId = null;
			}
		});
	}

	// --- Sending a placed visit back to the backlog ------------------------------------------------------

	// Taking work off the calendar is deliberate, so it always asks first -- both from the card's "Move to
	// Unscheduled" action and from a card dragged onto the open drawer. Clearing the date writes through the
	// same visit command a move uses; only the schedule half changes, the crew and instructions stay.
	function askUnschedule(visit: ScheduleVisit) {
		closePreview();
		pending = null;
		unscheduleError = '';
		unscheduleVisitId = visit.id;
	}

	function cancelUnschedule() {
		unscheduleVisitId = null;
		unscheduleError = '';
	}

	const unscheduleLabel = $derived(
		unscheduleVisitId && workingVisit ? visitWorkLabel(workingVisit) : 'this visit'
	);

	async function confirmUnschedule() {
		const visit = workingVisit;
		const jobVisit = workingJobVisit;
		if (!visit || !jobVisit) return;

		unscheduleSaving = true;
		unscheduleError = '';
		try {
			await updateJobVisit(visit.job_id, visit.id, jobVisit.revision, {
				visit_date: null,
				start_time: null,
				end_time: null,
				all_day: false,
				title: jobVisit.title,
				instructions: jobVisit.instructions,
				assignee_ids: jobVisit.assignee_ids
			});
			const jobId = visit.job_id;
			unscheduleVisitId = null;
			await refreshAfterWrite(jobId);
			toast.success('Visit moved to Unscheduled');
		} catch (caught) {
			const error = caught as JobWriteError;
			if (error.reason === 'stale' || error.reason === 'locked') {
				const jobId = visit.job_id;
				unscheduleVisitId = null;
				await refreshAfterWrite(jobId);
				toast.error(
					error.message ?? 'Someone else changed this visit. The latest version is now on screen.'
				);
			} else {
				unscheduleError =
					error.fieldErrors?.form ??
					error.message ??
					'That visit could not be moved to Unscheduled.';
			}
		} finally {
			unscheduleSaving = false;
		}
	}

	// FNV-1a over the ordered payload, the same fingerprint the Job page sends, so a retried request is
	// recognised as a replay of one intent rather than a second write.
	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	// A visit that moved changes the calendar, the job it belongs to and the job lists that count it.
	async function refreshAfterWrite(jobId: string) {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: ['schedule', 'window'] }),
			// The backlog gains a card when work is unscheduled or created undated, and loses one when a card is
			// placed, so every write that can change a date refreshes it.
			queryClient.invalidateQueries({ queryKey: scheduleUnscheduledKey }),
			queryClient.invalidateQueries({ queryKey: jobDetailKey(jobId) }),
			queryClient.invalidateQueries({ queryKey: jobEventsKey(jobId) }),
			queryClient.invalidateQueries({ queryKey: ['jobs', 'list'] }),
			queryClient.invalidateQueries({ queryKey: jobCountsKey })
		]);
	}

	async function saveMove(scope: 'single' | 'future') {
		const current = pending;
		const jobVisit = workingJobVisit;
		const change = pendingChange;
		if (!current || !jobVisit || !change) return;

		moveSaving = true;
		moveError = '';
		try {
			// Title and instructions travel back untouched. The update command replaces the whole visit, so
			// leaving them out of a move would quietly erase what the field crew is meant to read.
			const payload: UpdateVisitInput = {
				visit_date: current.proposal.visit_date,
				start_time: current.proposal.start_time,
				end_time: current.proposal.end_time,
				all_day: current.proposal.all_day,
				title: jobVisit.title,
				instructions: jobVisit.instructions,
				assignee_ids: current.proposal.assignee_ids
			};
			await updateJobVisit(current.visit.job_id, current.visit.id, jobVisit.revision, payload);

			if (scope === 'future') {
				const fields = futureScopeFields(change);
				const result = await applyVisitToFuture(
					current.visit.job_id,
					current.visit.id,
					fields,
					crypto.randomUUID(),
					fingerprint(fields)
				);
				toast.success(
					result.updated_count === 1
						? 'Visit moved, and 1 later visit updated'
						: `Visit moved, and ${result.updated_count} later visits updated`
				);
			} else {
				toast.success('Visit moved');
			}

			pending = null;
			await refreshAfterWrite(current.visit.job_id);
		} catch (caught) {
			const error = caught as JobWriteError;
			if (error.reason === 'stale' || error.reason === 'locked') {
				pending = null;
				await refreshAfterWrite(current.visit.job_id);
				toast.error(
					error.message ?? 'Someone else changed this visit. The latest version is now on screen.'
				);
			} else {
				moveError = error.fieldErrors?.form ?? error.message ?? 'That visit could not be moved.';
			}
		} finally {
			moveSaving = false;
		}
	}

	// The dialog path: the same Jobs form the Job page opens, so a keyboard user reaches every change a
	// drag can make. Saving goes through the same command with the same lock token.
	async function saveReschedule(payload: UpdateVisitInput, thenFuture: boolean) {
		const visit = workingVisit;
		const jobVisit = workingJobVisit;
		if (!visit || !jobVisit) return;

		rescheduleSaving = true;
		rescheduleError = '';
		try {
			await updateJobVisit(visit.job_id, visit.id, jobVisit.revision, payload);
			const jobId = visit.job_id;
			const laterFrom = payload.visit_date;
			closeReschedule();
			await refreshAfterWrite(jobId);
			toast.success('Visit saved');
			// "Save and update future visits" asks which settings to carry forward, exactly as it does on the
			// Job page. A visit with no date has no "later" to measure from, so it never opens.
			if (thenFuture && laterFrom) {
				applyTarget = { jobId, visitId: visit.id, label: visitWorkLabel(visit), date: laterFrom };
			}
		} catch (caught) {
			const error = caught as JobWriteError;
			if (error.reason === 'stale' || error.reason === 'locked') {
				const jobId = visit.job_id;
				closeReschedule();
				await refreshAfterWrite(jobId);
				toast.error(
					error.message ?? 'Someone else changed this visit. The latest version is now on screen.'
				);
			} else {
				rescheduleError =
					error.fieldErrors?.form ?? error.message ?? 'That visit could not be saved.';
			}
		} finally {
			rescheduleSaving = false;
		}
	}

	// --- Completing visits and the one-off job's final-visit decision ------------------------------------

	// Completion belongs to Jobs; the calendar only invokes the command and presents the result, exactly as the
	// Job page's Visits section does. It never invents a Schedule-only completion state. The same
	// `complete_job_visit`/`uncomplete_job_visit` commands run, so both screens report the same truth, and the
	// caches for both refresh after each write.

	/** The visit whose complete/uncomplete write is in flight, so its popover button shows the spinner. */
	let completingVisitId = $state<string | null>(null);

	// The one-off "final visit completed" question, opened only when the command reports final_visit true --
	// never on an idempotent replay. The job id is held so "Finish job" and "Add a return visit" know which job
	// they act on after the completed visit's popover has closed.
	let finalVisitOpen = $state(false);
	let finalVisitJobId = $state<string | null>(null);
	let closingFinal = $state(false);

	async function handleComplete(visit: ScheduleVisit) {
		completingVisitId = visit.id;
		try {
			const result = await completeJobVisit(visit.job_id, visit.id);
			await refreshAfterWrite(visit.job_id);
			toast.success('Visit marked complete');
			// Completing the last incomplete visit of a one-off job asks the finishing question. The popover for
			// the now-completed visit steps aside so the dialog stands on its own.
			if (result.final_visit) {
				closePreview();
				finalVisitJobId = visit.job_id;
				finalVisitOpen = true;
			}
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'That visit could not be marked complete.');
		} finally {
			completingVisitId = null;
		}
	}

	async function handleUncomplete(visit: ScheduleVisit) {
		completingVisitId = visit.id;
		try {
			await uncompleteJobVisit(visit.job_id, visit.id);
			await refreshAfterWrite(visit.job_id);
			toast.success('Visit marked incomplete');
		} catch (caught) {
			// A completed visit on an already-closed one-off job is refused here (reopen the job first); the
			// command's own message says so.
			toast.error((caught as JobWriteError).message ?? 'That visit could not be reopened.');
		} finally {
			completingVisitId = null;
		}
	}

	// "Finish job". close_job guards on the job's own revision, so the current one is read fresh right before the
	// write rather than carried from the completion -- completing a visit can bump the job in between.
	async function finishJob() {
		const jobId = finalVisitJobId;
		if (!jobId) return;
		closingFinal = true;
		try {
			const detail = await queryClient.fetchQuery({
				queryKey: jobDetailKey(jobId),
				queryFn: () => fetchJob(jobId)
			});
			await closeJob(jobId, detail.job.revision);
			finalVisitOpen = false;
			finalVisitJobId = null;
			await refreshAfterWrite(jobId);
			toast.success('Job finished');
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'That job could not be closed.');
		} finally {
			closingFinal = false;
		}
	}

	// "Add a return visit". The same day-picking dialog the Job page uses; the chosen days are appended to the
	// job through the Jobs-owned add command, tagged as a return trip so the history reads truthfully.
	let returnVisitJobId = $state<string | null>(null);
	let returnVisitOpen = $state(false);

	function openReturnVisit() {
		if (!finalVisitJobId) return;
		returnVisitJobId = finalVisitJobId;
		finalVisitOpen = false;
		finalVisitJobId = null;
		returnVisitOpen = true;
	}

	function closeReturnVisit() {
		returnVisitOpen = false;
		returnVisitJobId = null;
	}

	async function handleReturnCreate(result: { dates: string[]; scheduleLater: boolean }) {
		// The dialog closes at once and the add runs behind it, the same way the Job page's Add-visits does, so
		// the picker never lingers over a network call. The job id is captured first because closing clears it.
		const jobId = returnVisitJobId;
		if (!jobId) return;
		closeReturnVisit();
		try {
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
							source: 'return'
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
						source: 'return' as const
					}));
			await addJobVisits(jobId, items, crypto.randomUUID(), fingerprint(items));
			await refreshAfterWrite(jobId);
			toast.success(items.length === 1 ? 'Return visit added' : `${items.length} visits added`);
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'Those visits could not be added.');
		}
	}

	// --- Creating a job from empty calendar space --------------------------------------------------------

	// The Job is the agreement; a Visit is one occurrence of it. So empty calendar space starts a Job, not a
	// loose visit: a compact form seeded with the day, time and team the gesture proposed. Save writes through
	// the Jobs-owned create command -- the same one the New Job page uses -- creating the Job and its first
	// Visit in one go. More Options carries the same draft to that full page for line items and the rest.
	// There is one Job create contract and no schedule-owned Job or Visit truth.

	let createOpen = $state(false);
	let createDraft = $state<NewVisitDraft | null>(null);
	let createSaving = $state(false);
	let createError = $state('');

	function openCreate(draft: NewVisitDraft | null) {
		closePreview();
		pending = null;
		createDraft = draft;
		createError = '';
		createOpen = true;
	}

	function closeCreate() {
		createOpen = false;
		createDraft = null;
		createError = '';
	}

	// The first Visit as the create command wants it: a job carries its visits, and this one carries the
	// schedule and team the calendar gesture seeded. Its title is left blank so the Visit reads under the
	// Job's title unless someone renames it later.
	function seedVisitInput(seed: JobCreateSeed): JobVisitInput {
		const visit = seed.first_visit;
		return {
			position: 0,
			visit_date: visit?.visit_date ?? null,
			start_time: visit?.start_time ?? null,
			end_time: visit?.end_time ?? null,
			all_day: visit?.all_day ?? false,
			title: null,
			instructions: visit?.instructions ?? null,
			assignee_ids: visit?.assignee_ids ?? []
		};
	}

	async function saveJobCreate(seed: JobCreateSeed) {
		if (!seed.client) {
			createError = 'Choose a client to continue.';
			return;
		}
		createSaving = true;
		createError = '';
		try {
			const core = {
				client_id: seed.client.id,
				property_id: seed.property_id,
				title: seed.title,
				// The compact form has no job-level instructions; each visit carries its own, as on the Job page.
				instructions: null,
				invoice_on_close: true,
				job_type: 'one_off' as const,
				is_as_needed: false,
				recurrence: null,
				lines: [],
				visits: [seedVisitInput(seed)]
			};
			const payload: CreateJobPayload = {
				...core,
				idempotency_key: crypto.randomUUID(),
				request_hash: fingerprint(core)
			};
			const result = await createJob(payload);
			closeCreate();
			await refreshAfterWrite(result.job_id);
			toast.success(`Job #${result.job_number} created`);
		} catch (caught) {
			const error = caught as JobWriteError;
			createError = error.fieldErrors?.form ?? error.message ?? 'That job could not be saved.';
		} finally {
			createSaving = false;
		}
	}

	// More Options: stage the draft and open the full New Job page, which reads it once and opens filled.
	function openMoreOptions(seed: JobCreateSeed) {
		stageJobCreateSeed(seed);
		closeCreate();
		void goto(resolve('/(app)/jobs/new'));
	}

	// Request: the empty-slot chooser's other type. Schedule owns no Request or Assessment truth, so it only
	// stages the clicked slot and opens the Request-owned New Request page, where its on-site assessment reads
	// the slot once and opens pre-booked. An existing Request still schedules its assessment from its own
	// surface, never from here.
	function openRequestCreate(seed: AssessmentCreateSeed) {
		stageAssessmentSeed(seed);
		closeCreate();
		void goto(resolve('/(app)/requests/new'));
	}

	let applyTarget = $state<{
		jobId: string;
		visitId: string;
		label: string;
		date: string;
	} | null>(null);
	let applySaving = $state(false);
	let applyError = $state('');

	// The same rule the command uses: a later visit is a dated, incomplete one strictly after this one's day.
	const applyLaterCount = $derived(
		applyTarget
			? (jobQuery.data?.visits ?? []).filter(
					(visit) =>
						visit.id !== applyTarget!.visitId &&
						!visit.completed_at &&
						visit.visit_date !== null &&
						visit.visit_date > applyTarget!.date
				).length
			: 0
	);

	async function confirmApplyFuture(fields: { time_of_day: boolean; assigned_team: boolean }) {
		const target = applyTarget;
		if (!target) return;
		applySaving = true;
		applyError = '';
		try {
			const result = await applyVisitToFuture(
				target.jobId,
				target.visitId,
				fields,
				crypto.randomUUID(),
				fingerprint(fields)
			);
			applyTarget = null;
			await refreshAfterWrite(target.jobId);
			toast.success(
				result.updated_count === 1
					? '1 later visit updated'
					: `${result.updated_count} later visits updated`
			);
		} catch (caught) {
			applyError =
				(caught as JobWriteError).message ??
				'Those settings could not be applied to the later visits.';
		} finally {
			applySaving = false;
		}
	}

	/** How the page names the window it is showing, for a note that has to say where the work went. */
	const WINDOW_WORDS: Record<ScheduleView, string> = {
		day: 'on this day',
		week: 'this week',
		month: 'this month'
	};

	const dayHeadingFormat: Intl.DateTimeFormatOptions = {
		weekday: 'long',
		month: 'short',
		day: 'numeric'
	};

	const rangeLabel = $derived.by(() => {
		if (!filters || !activeWindow) return '';
		if (filters.view === 'month') {
			// The month window starts on the Sunday before the 1st, which can belong to the month before it.
			// The name of the month comes from the date the calendar is anchored to, never from that Sunday.
			return formatCalendarDay(filters.date, { month: 'long', year: 'numeric' });
		}
		if (filters.view === 'day') {
			return formatCalendarDay(activeWindow.from, {
				weekday: 'long',
				month: 'long',
				day: 'numeric',
				year: 'numeric'
			});
		}
		const sameYear = activeWindow.from.slice(0, 4) === activeWindow.to.slice(0, 4);
		const start = formatCalendarDay(activeWindow.from, {
			month: 'short',
			day: 'numeric',
			...(sameYear ? {} : { year: 'numeric' })
		});
		const end = formatCalendarDay(activeWindow.to, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
		return `${start} – ${end}`;
	});
</script>

<svelte:head><title>Schedule · UpliftContractor</title></svelte:head>

<PageContainer variant="fill">
	<div class="schedule-page">
		<PageHeader title="Schedule" description="The work your team is committed to.">
			{#snippet actions()}
				<!-- The primary create action. In Version 1.1 it opens the same Job/Request chooser an empty
				     slot does, seeded with no date, so the work is scheduled from inside the form. Empty
				     calendar space seeds a date instead. -->
				<Button variant="primary" disabled={!canCreate} onclick={() => openCreate(null)}>
					New
				</Button>
			{/snippet}
		</PageHeader>

		{#if contextQuery.isPending}
			<LoadingSkeleton variant="card" rows={2} label="Loading the calendar" />
		{:else if contextQuery.isError || !filters}
			<ErrorState
				title="The calendar could not start"
				description="We could not read your business timezone, so no day on this page would be right."
				retry={() => void contextQuery.refetch()}
			/>
		{:else}
			<ScheduleControls
				{filters}
				{rangeLabel}
				employees={teamQuery.data ?? []}
				employeesFailed={teamQuery.isError}
				{zoom}
				showZoom={filters.view !== 'month'}
				{unscheduledCount}
				{unscheduledOpen}
				onstep={step}
				ontoday={goToToday}
				onchange={changeFilters}
				onzoom={changeZoom}
				onunscheduled={() => (unscheduledOpen = !unscheduledOpen)}
				onunscheduledhover={() => (unscheduledWarm = true)}
			/>

			<!-- The calendar and the docked backlog sit side by side, so a card can be dragged straight out of
			     the drawer onto the grid while both stay in view. -->
			<div class="schedule-page__workspace">
				<div class="schedule-page__calendar">
					{#if windowQuery.isPending}
						<LoadingSkeleton variant="card" rows={4} label="Loading this window" />
					{:else if windowQuery.isError}
						<ErrorState
							title="This part of the calendar could not load"
							description="The dates and filters you chose are still here. Try again."
							retry={() => void windowQuery.refetch()}
						/>
					{:else}
						{#if windowQuery.data?.truncated}
							<p class="schedule-page__notice" role="status">
								This window holds more than {windowQuery.data.limit} visits, so only the first {windowQuery
									.data.limit} are shown. Pick a shorter range to see all of them.
							</p>
						{/if}

						<!-- A calendar always draws its grid. When a filter empties it, the grid stays and says so,
				     rather than being replaced by a page that has lost the dates. -->
						{#if filteredEmpty}
							<p class="schedule-page__notice schedule-page__notice--quiet" role="status">
								There is work {WINDOW_WORDS[filters.view]}, but none of it matches the employee or
								status you picked.
							</p>
						{/if}

						{#if filters.view === 'week'}
							<ScheduleWeek
								bind:this={weekGrid}
								window={activeWindow!}
								items={visibleItems}
								today={today!}
								nowMinutes={activeWindow!.from <= today! && today! <= activeWindow!.to
									? nowMinutes
									: null}
								workingWeek={workingHours}
								{employeesById}
								{selectedItemId}
								{canSchedule}
								{canCreate}
								{zoom}
								movingVisitId={pending?.visit.id ?? null}
								unscheduleZone={unscheduleDropZone}
								onselect={openPreview}
								onselectassessment={openAssessmentPreview}
								onpropose={proposeChange}
								oncreate={openCreate}
								onunschedule={(visit) => askUnschedule(visit)}
							/>
						{:else if filters.view === 'day'}
							<ScheduleDay
								bind:this={dayGrid}
								day={activeWindow!.from}
								items={visibleItems}
								team={teamQuery.data ?? []}
								today={today!}
								nowMinutes={activeWindow!.from === today ? nowMinutes : null}
								workingWeek={workingHours}
								employeeFilter={filters.employee}
								{employeesById}
								{selectedItemId}
								{canSchedule}
								{canCreate}
								{zoom}
								movingVisitId={pending?.visit.id ?? null}
								unscheduleZone={unscheduleDropZone}
								onselect={openPreview}
								onselectassessment={openAssessmentPreview}
								onpropose={proposeChange}
								oneditassignment={(visit) => openReschedule(visit)}
								oncreate={openCreate}
								onunschedule={(visit) => askUnschedule(visit)}
							/>
						{:else}
							<ScheduleMonth
								window={activeWindow!}
								anchorDate={filters.date}
								items={visibleItems}
								today={today!}
								{employeesById}
								{selectedItemId}
								{canCreate}
								onselect={openPreview}
								onselectassessment={openAssessmentPreview}
								oncreate={openCreate}
							/>
						{/if}
					{/if}
				</div>

				{#if unscheduledOpen}
					<ScheduleUnscheduledDrawer
						visits={unscheduledQuery.data?.visits ?? []}
						loading={unscheduledQuery.isPending}
						error={unscheduledQuery.isError
							? ((unscheduledQuery.error as Error)?.message ??
								'The unscheduled work could not be loaded.')
							: ''}
						truncated={unscheduledQuery.data?.truncated ?? false}
						limit={unscheduledQuery.data?.limit}
						today={today!}
						employees={teamQuery.data ?? []}
						{employeesById}
						{canSchedule}
						bind:query={backlogQuery}
						bind:employee={backlogEmployee}
						bind:dropZone={unscheduleDropZone}
						{placingVisitId}
						onClose={() => (unscheduledOpen = false)}
						onRetry={() => void unscheduledQuery.refetch()}
						onSchedule={(visit) => openReschedule(visit)}
						onPreview={openPreview}
						onPickUp={pickUpFromBacklog}
					/>
				{/if}
			</div>
		{/if}
	</div>
</PageContainer>

{#if selectedVisit && today}
	<Popover
		open
		anchor={previewAnchor}
		title={visitClientLabel(selectedVisit)}
		onClose={closePreview}
	>
		<VisitPreview
			visit={selectedVisit}
			{today}
			dayLabel={selectedVisit.visit_date
				? formatCalendarDay(selectedVisit.visit_date, dayHeadingFormat)
				: 'Not scheduled'}
			{employeesById}
			{canSchedule}
			{canComplete}
			completing={completingVisitId === selectedVisit.id}
			onreschedule={() => openReschedule(selectedVisit)}
			onunschedule={() => askUnschedule(selectedVisit)}
			oncomplete={() => void handleComplete(selectedVisit)}
			onuncomplete={() => void handleUncomplete(selectedVisit)}
		/>
	</Popover>
{/if}

<!-- An assessment's own preview. It is Request-owned, so this only reads it and opens the Request; there is no
     reschedule, complete or unschedule here. -->
{#if selectedAssessment && today}
	<Popover
		open
		anchor={previewAnchor}
		title={selectedAssessment.client_name ??
			selectedAssessment.client_company_name ??
			'Client hidden'}
		onClose={closePreview}
	>
		<AssessmentPreview
			assessment={selectedAssessment}
			{today}
			dayLabel={selectedAssessment.visit_date
				? formatCalendarDay(selectedAssessment.visit_date, dayHeadingFormat)
				: 'Not scheduled'}
			{employeesById}
		/>
	</Popover>
{/if}

<!-- A drag has landed. Nothing is written until this is saved, so the proposal, its consequences and its
     scope all sit in front of the person first. -->
{#if pending && pendingChange}
	<Popover open anchor={pending.anchor} title="Move visit" onClose={cancelMove}>
		<MoveConfirm
			visit={pending.visit}
			proposal={pending.proposal}
			change={pendingChange}
			warnings={pendingWarnings}
			{employeesById}
			recurring={jobQuery.data?.recurrence !== null && jobQuery.data?.recurrence !== undefined}
			loading={jobQuery.isPending || jobQuery.isFetching}
			saving={moveSaving}
			error={moveError}
			onsave={saveMove}
			oncancel={cancelMove}
		/>
	</Popover>
{/if}

<!-- The button and keyboard path to the same changes: the Job page's own visit form, opened here. -->
<JobVisitDialog
	open={rescheduleVisitId !== null && workingJobVisit !== null && !jobQuery.isFetching}
	visit={workingJobVisit}
	jobTitle={jobQuery.data?.job.title ?? ''}
	locale={jobQuery.data?.locale ?? 'en-US'}
	isRecurring={jobQuery.data?.recurrence !== null && jobQuery.data?.recurrence !== undefined}
	saving={rescheduleSaving}
	error={rescheduleError}
	onSave={(payload) => void saveReschedule(payload, false)}
	onSaveFuture={(payload) => void saveReschedule(payload, true)}
	onClose={closeReschedule}
/>

<!-- Starting a job from empty calendar space: a compact create form seeded with the gesture's day, time and
     team, writing through the same Jobs-owned create command the New Job page uses. More Options carries the
     draft to that full page. -->
<ScheduleJobCreate
	open={createOpen}
	draft={createDraft}
	saving={createSaving}
	error={createError}
	onCreate={(seed) => void saveJobCreate(seed)}
	onMoreOptions={openMoreOptions}
	onCreateRequest={openRequestCreate}
	onClose={closeCreate}
/>

<!-- The one-off "final visit completed" decision: Finish job, Add a return visit, or Keep open. "Finish job"
     is hidden for a reader without the close authority; the other two need none. -->
<FinalVisitDialog
	open={finalVisitOpen}
	{canClose}
	closing={closingFinal}
	onFinish={() => void finishJob()}
	onAddReturnVisit={openReturnVisit}
	onKeepOpen={() => {
		finalVisitOpen = false;
		finalVisitJobId = null;
	}}
/>

<!-- "Add a return visit" from the final-visit dialog: the same day-picker the Job page uses, appending the
     chosen days to this job through the Jobs-owned add command. -->
<CreateVisitsDialog
	open={returnVisitOpen}
	onClose={closeReturnVisit}
	onCreate={handleReturnCreate}
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

<!-- Taking work off the calendar is deliberate, so it is always confirmed -- whether the person dragged the
     card into the drawer or used the card's "Move to Unscheduled" action. -->
<ConfirmDialog
	open={unscheduleVisitId !== null}
	title="Move to Unscheduled?"
	confirmLabel="Move to Unscheduled"
	cancelLabel="Keep on calendar"
	loading={unscheduleSaving}
	confirmDisabled={jobQuery.isPending || jobQuery.isFetching || workingJobVisit === null}
	onConfirm={() => void confirmUnschedule()}
	onClose={cancelUnschedule}
>
	<p>
		This clears the date and time for <strong>{unscheduleLabel}</strong> and moves it to the Unscheduled
		list, where you can place it again later. The job and its crew stay the same.
	</p>
	{#if unscheduleError}
		<p class="schedule-page__dialog-error" role="alert">{unscheduleError}</p>
	{/if}
</ConfirmDialog>

<!-- The chip the person is carrying: it follows the pointer while a backlog card is dragged onto the grid,
     so the drag reads as moving that piece of work, not just a cursor. -->
{#if dragGhost}
	<div
		class="schedule-page__ghost"
		style:left="{dragGhost.x}px"
		style:top="{dragGhost.y}px"
		aria-hidden="true"
	>
		{dragGhost.label}
	</div>
{/if}

<style lang="scss">
	.schedule-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	// The calendar takes the room and the backlog docks beside it. The calendar column can shrink (min-width:
	// 0) so the drawer's fixed width never squeezes it out of the row.
	.schedule-page__workspace {
		display: flex;
		align-items: flex-start;
		gap: var(--space-large);
	}

	.schedule-page__calendar {
		display: flex;
		flex: 1 1 auto;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-base);
	}

	.schedule-page__dialog-error {
		margin: var(--space-small) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	// A light chip that trails the pointer during an external drag. It must never eat the pointer events the
	// grid probe relies on, so it is click-through.
	.schedule-page__ghost {
		position: fixed;
		z-index: var(--elevation-modal);
		transform: translate(12px, 12px);
		max-width: 220px;
		padding: var(--space-smaller) var(--space-small);
		border: var(--border-base) solid var(--color-interactive);
		border-radius: var(--radius-small);
		background-color: var(--color-surface);
		box-shadow: var(--shadow-high);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		pointer-events: none;
	}

	.schedule-page__notice {
		padding: var(--space-slim);
		border: var(--border-base) solid var(--color-warning);
		border-radius: var(--radius-base);
		background-color: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);

		&--quiet {
			border-color: var(--color-border);
			background-color: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
		}
	}
</style>
