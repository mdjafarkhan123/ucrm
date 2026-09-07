<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import { Time } from '@internationalized/date';
	import {
		dateTimePickerValueFromDate,
		dateTimePickerValueToLocalString,
		emptyDateTimePickerValue,
		timeToMinutes,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { JobTimeEntry, JobTimeEntryInput, JobVisit } from '$lib/jobs/api';

	// One entry of work, recorded or corrected. Jobber's dialog also carries the person's hourly cost and the
	// total it produces; ours does not, on purpose — the rate lives on the person's team profile and is copied
	// onto the entry by the command, which is what stops a rate change from re-pricing finished work, and what
	// keeps the money off a screen a crew member may be looking at.
	//
	// Duration is hours and minutes against a start time, matching how the entry is stored. An end time would
	// be a second way to say the same thing and a timezone argument at every edit.
	let {
		open,
		entry = null,
		visits = [],
		locale = 'en-US',
		canPickPerson = false,
		currentUserId = '',
		saving = false,
		error = '',
		onSave,
		onClose
	}: {
		open: boolean;
		/** The entry being corrected, or null when recording new hours. */
		entry?: JobTimeEntry | null;
		visits?: JobVisit[];
		locale?: string;
		/** Whether this person records for the whole crew. Without it the entry is always their own. */
		canPickPerson?: boolean;
		currentUserId?: string;
		saving?: boolean;
		error?: string;
		onSave: (input: JobTimeEntryInput) => void;
		onClose: () => void;
	} = $props();

	let userId = $state('');
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let hours = $state<string | number | null>(1);
	let minutes = $state<string | number | null>(0);
	let visitId = $state('');
	let notes = $state('');
	let fieldError = $state('');

	// The crew list is only worth fetching while the dialog is open and this person may record for others.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: open && canPickPerson,
		staleTime: 5 * 60 * 1000
	}));
	const team = $derived<TeamMember[]>(teamQuery.data ?? []);
	const personOptions = $derived(
		team.map((member) => ({ value: member.id, label: member.full_name ?? 'A team member' }))
	);

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	const visitOptions = $derived([
		{ value: '', label: 'No particular visit' },
		...visits.map((visit) => ({
			value: visit.id,
			label: visit.visit_date
				? `${visit.title?.trim() || 'Visit'} · ${dateFormat.format(new Date(`${visit.visit_date}T12:00:00`))}`
				: visit.title?.trim() || 'Unscheduled visit'
		}))
	]);

	// Read the entry into the form each time the dialog opens, never while it is open, so typing is never
	// overwritten by a background refetch.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			if (entry) {
				userId = entry.user_id;
				when = dateTimePickerValueFromDate(new Date(entry.started_at));
				hours = Math.floor(entry.minutes / 60);
				minutes = entry.minutes % 60;
				visitId = entry.visit_id ?? '';
				notes = entry.notes ?? '';
			} else {
				userId = currentUserId;
				when = dateTimePickerValueFromDate(new Date());
				hours = 1;
				minutes = 0;
				visitId = '';
				notes = '';
			}
			fieldError = '';
		}
		wasOpen = open;
	});

	function toWholeNumber(value: string | number | null) {
		const parsed = typeof value === 'number' ? value : Number(value ?? 0);
		return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
	}

	const totalMinutes = $derived(toWholeNumber(hours) * 60 + toWholeNumber(minutes));

	// The duration is the one truth; the end time is a view of it that can be typed into. Holding it the
	// other way round -- two boxes that each own a fact -- is how a start/end pair and an hours/minutes pair
	// end up disagreeing, which is exactly what the stored column avoids by keeping only minutes.
	//
	// Both directions wrap past midnight rather than clamping at 23:59: an evening call-out that finishes at
	// 1 AM is a real shift, and the 24-hour ceiling still refuses anything absurd.
	const endTime = $derived.by(() => {
		const start = timeToMinutes(when.startTime);
		if (start === undefined || totalMinutes < 1) return undefined;
		const total = (start + totalMinutes) % 1440;
		return new Time(Math.floor(total / 60), total % 60);
	});

	function setEndTime(next: Time | undefined) {
		const start = timeToMinutes(when.startTime);
		const end = timeToMinutes(next);
		if (start === undefined || end === undefined) return;
		const spanned = (end - start + 1440) % 1440;
		hours = Math.floor(spanned / 60);
		minutes = spanned % 60;
	}

	function submit() {
		fieldError = '';
		if (!userId) {
			fieldError = 'Choose whose hours these are.';
			return;
		}
		const local = dateTimePickerValueToLocalString(when);
		if (!local) {
			fieldError = 'Pick the day and time this work started.';
			return;
		}
		const startedAt = new Date(local);
		if (Number.isNaN(startedAt.getTime())) {
			fieldError = 'Pick the day and time this work started.';
			return;
		}
		if (totalMinutes < 1) {
			fieldError = 'Enter how long this took.';
			return;
		}
		if (totalMinutes > 1440) {
			fieldError = 'A single entry cannot be longer than 24 hours.';
			return;
		}

		onSave({
			user_id: userId,
			started_at: startedAt.toISOString(),
			minutes: totalMinutes,
			visit_id: visitId || null,
			notes: notes.trim() || null
		});
	}
</script>

<Dialog {open} title={entry ? 'Edit time entry' : 'New time entry'} size="small" {onClose}>
	<div class="time-entry">
		{#if error}<p class="time-entry__alert" role="alert">{error}</p>{/if}
		{#if fieldError}<p class="time-entry__alert" role="alert">{fieldError}</p>{/if}

		{#if entry}
			<p class="time-entry__note">
				These hours stay recorded for {entry.user_name ?? 'the same person'}. To move them to
				someone else, record them again and remove this entry.
			</p>
		{:else if canPickPerson}
			<Select
				id="time-entry-person"
				label="Whose hours"
				placeholder={teamQuery.isPending ? 'Loading your team…' : 'Choose a team member'}
				options={personOptions}
				bind:value={userId}
			/>
		{/if}

		<DateTimePicker
			id="time-entry-when"
			dateLabel="Day"
			timeLabel="Started at"
			{locale}
			bind:value={when}
		/>

		<!--
			Jobber offers the end time and the duration together, because a contractor says "nine to five" far
			more naturally than "eight hours". Both are here, and both stay in step: the end time is drawn from
			the duration, and typing an end time sets the duration.
		-->
		<div class="time-entry__ended">
			<TimePickerField
				id="time-entry-end"
				label="Ended at"
				value={endTime}
				disabled={!when.startTime}
				onchange={setEndTime}
			/>
		</div>

		<!-- A placeholder on both, so the label still lifts clear when the box holds a plain 0. -->
		<div class="time-entry__duration">
			<Input
				id="time-entry-hours"
				label="Hours"
				type="number"
				min="0"
				max="24"
				placeholder="0"
				bind:value={hours}
			/>
			<Input
				id="time-entry-minutes"
				label="Minutes"
				type="number"
				min="0"
				max="59"
				placeholder="0"
				bind:value={minutes}
			/>
		</div>

		{#if visits.length > 0}
			<Select
				id="time-entry-visit"
				label="Visit (optional)"
				options={visitOptions}
				bind:value={visitId}
			/>
		{/if}

		<Textarea
			id="time-entry-notes"
			label="Notes (optional)"
			rows={3}
			maxlength={2000}
			bind:value={notes}
		/>

		<div class="time-entry__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={submit}>
				{entry ? 'Save hours' : 'Record hours'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.time-entry {
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

		&__ended {
			// Half width, so it lines up with the Hours box directly under it rather than stretching across
			// a row of its own.
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-small);
		}

		&__duration {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
