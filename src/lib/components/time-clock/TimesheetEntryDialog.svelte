<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { Time, type CalendarDate } from '@internationalized/date';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import JobPicker from '$lib/components/work/JobPicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { fetchJob, jobDetailKey } from '$lib/jobs/api';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { durationLabel } from '$lib/time-clock/api';
	import {
		addTimesheetEntry,
		businessClock,
		refreshAfterCorrection,
		spanMinutes,
		updateRunningTimer,
		updateTimesheetEntry,
		type CorrectionError,
		type EntryDialogMode,
		type PickedJob
	} from '$lib/time-clock/corrections';

	// Add or correct an entry from Timesheets (plan § Timesheets page): what it was for (a Job and, optionally,
	// its visit, or General; Assessment hours may also stay on their own Assessment), the day, start and end
	// times, and notes; a manager also picks the person. The
	// duration is worked out from the times, as Jobber's timesheet does. While a timer runs only its start and
	// notes can change. Times are the business's own clock, the same one the page shows.
	let {
		open,
		mode,
		timezone,
		people = [],
		canPickPerson = false,
		onClose
	}: {
		open: boolean;
		mode: EntryDialogMode | null;
		timezone: string;
		/** Whose hours these may be, for someone who records for the team. */
		people?: { value: string; label: string }[];
		canPickPerson?: boolean;
		onClose: () => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();

	let userId = $state('');
	let forWhat = $state<'job' | 'general' | 'assessment'>('job');
	let jobId = $state('');
	let pickedJob = $state<PickedJob | null>(null);
	let visitId = $state('');
	let day = $state<CalendarDate | undefined>();
	let start = $state<Time | undefined>();
	let end = $state<Time | undefined>();
	let notes = $state('');
	let saving = $state(false);
	let error = $state('');
	// The picker is drawn afresh for each opening, so it starts from that entry's Job.
	let openCount = $state(0);

	const running = $derived(mode?.kind === 'running');
	const editing = $derived(mode?.kind === 'edit');
	// Hours are only put on an Assessment by its timer, so the choice is offered only to keep them there.
	const assessmentRequest = $derived(
		mode?.kind === 'edit' && mode.entry.kind === 'assessment' ? mode.entry.request : null
	);
	const forOptions = $derived([
		{ value: 'job', label: 'A job' },
		...(assessmentRequest ? [{ value: 'assessment', label: 'This assessment' }] : []),
		{ value: 'general', label: 'General' }
	]);

	function toTime(clock: string) {
		const [hours, minutes] = clock.split(':').map(Number);
		return new Time(hours, minutes);
	}

	function toClock(time: Time | undefined) {
		if (!time) return '';
		return `${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}`;
	}

	// Read the entry into the form each time the dialog opens, never while it is open, so typing is never
	// overwritten by a background refetch.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen && mode) {
			error = '';
			saving = false;
			openCount += 1;
			userId = mode.userId;
			if (mode.kind === 'add') {
				forWhat = 'job';
				jobId = '';
				pickedJob = null;
				visitId = '';
				day = calendarDateFromString(mode.day);
				start = new Time(8, 0);
				end = new Time(16, 0);
				notes = '';
			} else {
				const entry = mode.entry;
				const begun = businessClock(entry.started_at, timezone);
				forWhat = entry.kind;
				jobId = entry.job?.id ?? '';
				pickedJob = entry.job
					? { id: entry.job.id, job_number: entry.job.number, title: entry.job.title ?? '' }
					: null;
				visitId = entry.visit_id ?? '';
				day = calendarDateFromString(begun.day);
				start = toTime(begun.time);
				end = entry.ended_at ? toTime(businessClock(entry.ended_at, timezone).time) : undefined;
				notes = entry.notes ?? '';
			}
		}
		wasOpen = open;
	});

	// The chosen Job's visits, to pin the hours to one. Only read once a Job is chosen in an open dialog.
	const jobQuery = createQuery(() => ({
		queryKey: jobDetailKey(jobId),
		queryFn: () => fetchJob(jobId),
		enabled: open && !running && forWhat === 'job' && Boolean(jobId),
		staleTime: 60_000
	}));
	const visitOptions = $derived([
		{ value: '', label: 'No particular visit' },
		...(jobQuery.data?.visits ?? []).map((visit) => ({
			value: visit.id,
			label: visit.visit_date
				? `${visit.title?.trim() || 'Visit'} · ${formatCalendarDay(visit.visit_date, { month: 'short', day: 'numeric', year: 'numeric' })}`
				: visit.title?.trim() || 'Unscheduled visit'
		}))
	]);

	const minutes = $derived(start && end ? spanMinutes(toClock(start), toClock(end)) : null);
	const nextDay = $derived(Boolean(start && end && toClock(end) <= toClock(start)));

	const title = $derived(
		mode?.kind === 'add' ? 'Add time entry' : running ? 'Edit running timer' : 'Edit time entry'
	);

	function chooseJob(job: PickedJob | null) {
		pickedJob = job;
		jobId = job?.id ?? '';
		visitId = '';
	}

	async function save() {
		if (saving || !mode) return;
		error = '';
		const dayText = calendarDateToString(day);
		if (!dayText || !start) {
			error = 'Choose the day and the start time.';
			return;
		}
		if (!running) {
			if (!userId) {
				error = 'Choose whose hours these are.';
				return;
			}
			if (forWhat === 'job' && !jobId) {
				error = 'Choose the job these hours were for, or General.';
				return;
			}
			if (!end) {
				error = 'Choose the end time.';
				return;
			}
			if (toClock(start) === toClock(end)) {
				error = 'The end time must be different from the start time.';
				return;
			}
		}

		saving = true;
		try {
			if (mode.kind === 'running') {
				await updateRunningTimer(mode.userId, {
					day: dayText,
					start_time: toClock(start),
					notes: notes.trim() || null
				});
			} else {
				const input = {
					user_id: userId,
					job_id: forWhat === 'job' ? jobId : null,
					visit_id: forWhat === 'job' && visitId ? visitId : null,
					request_id: forWhat === 'assessment' ? (assessmentRequest?.id ?? null) : null,
					day: dayText,
					start_time: toClock(start),
					end_time: toClock(end),
					notes: notes.trim() || null
				};
				if (mode.kind === 'edit') await updateTimesheetEntry(mode.entry.id, input);
				else await addTimesheetEntry(input);
			}
			await refreshAfterCorrection(queryClient);
			toast.success(mode.kind === 'add' ? 'Hours added' : 'Changes saved');
			onClose();
		} catch (cause) {
			error = (cause as CorrectionError).message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} {title} size="small" onClose={() => !saving && onClose()}>
	<form
		class="entry-form"
		onsubmit={(event) => {
			event.preventDefault();
			void save();
		}}
	>
		{#if error}<p class="entry-form__alert" role="alert">{error}</p>{/if}

		{#if mode?.kind === 'edit' && mode.entry.approved}
			<!-- Only someone who manages the team's time reaches this (plan § Weekly approval). -->
			<Banner type="notice">
				These hours are approved. They stay approved after your change, and the change is kept in
				the entry’s history.
			</Banner>
		{/if}

		{#if running}
			<p class="entry-form__note">
				This timer is still running, so only its start time and notes can change. Its hours are
				recorded when it stops.
			</p>
		{:else}
			{#if canPickPerson}
				<Select
					id="entry-person"
					label="Whose hours"
					placeholder="Choose a team member"
					options={people}
					bind:value={userId}
				/>
			{/if}

			<SegmentedControl
				label="For"
				name="entry-for"
				fullWidth
				options={forOptions}
				value={forWhat}
				onchange={(next) => (forWhat = next as 'job' | 'general' | 'assessment')}
			/>

			{#if forWhat === 'job'}
				{#key openCount}
					<JobPicker
						id="entry-job"
						required
						bind:value={jobId}
						initialJob={pickedJob}
						onSelect={chooseJob}
					/>
				{/key}
				{#if jobId && (jobQuery.data?.visits.length ?? 0) > 0}
					<Select
						id="entry-visit"
						label="Visit (optional)"
						options={visitOptions}
						bind:value={visitId}
					/>
				{/if}
			{:else if forWhat === 'assessment'}
				<p class="entry-form__note">
					Time at the on-site assessment{assessmentRequest?.title
						? ` for ${assessmentRequest.title}`
						: ''}. It has no job cost.
				</p>
			{:else}
				<p class="entry-form__note">Paid time on no job, such as travel or time at the shop.</p>
			{/if}
		{/if}

		<CalendarPicker id="entry-day" label={running ? 'Started on' : 'Day'} bind:value={day} />

		<div class="entry-form__times">
			<TimePickerField id="entry-start" label="Started at" bind:value={start} />
			{#if !running}
				<TimePickerField id="entry-end" label="Ended at" bind:value={end} />
			{/if}
		</div>

		{#if !running && minutes !== null && toClock(start) !== toClock(end)}
			<p class="entry-form__duration" aria-live="polite">
				<span>Duration</span>
				<strong>{durationLabel(minutes)}</strong>
				{#if nextDay}<span class="entry-form__next-day">Ends the next day</span>{/if}
			</p>
		{/if}

		<Textarea
			id="entry-notes"
			label="Notes (optional)"
			rows={3}
			maxlength={2000}
			bind:value={notes}
		/>

		<div class="entry-form__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" type="submit" loading={saving}>
				{mode?.kind === 'add' ? 'Add hours' : 'Save changes'}
			</Button>
		</div>
		{#if editing && mode?.kind === 'edit' && mode.entry.job?.closed}
			<p class="entry-form__note">
				This job is closed. Your change is recorded in its costing history.
			</p>
		{/if}
	</form>
</Dialog>

<style lang="scss">
	.entry-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__times {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-small);
		}

		&__duration {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-variant-numeric: tabular-nums;
			}
		}

		&__next-day {
			margin-left: auto;
			color: var(--color-informative--onSurface);
			font-weight: 600;
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}

	/* Two time fields side by side leave too little room for "12:00 PM" on a phone. */
	@media (max-width: 479px) {
		.entry-form__times {
			grid-template-columns: 1fr;
		}
	}
</style>
