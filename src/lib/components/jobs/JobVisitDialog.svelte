<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeFromString,
		timeToString,
		emptyDateTimePickerValue,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { JobVisit, UpdateVisitInput } from '$lib/jobs/api';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	// Editing one existing visit, the way a client's property is edited: its own modal with its own Save, kept
	// out of the page's title/instructions draft. The dialog only shapes the visit and hands the result back;
	// the section that owns the list does the write, so saving state and server errors come in as props.
	let {
		open,
		visit,
		jobTitle = '',
		locale = 'en-US',
		isRecurring = false,
		saving = false,
		error = '',
		onSave,
		onSaveFuture,
		onClose
	}: {
		open: boolean;
		visit: JobVisit | null;
		jobTitle?: string;
		locale?: string;
		// A recurring job's visit can carry its settings forward; the section wires the follow-up dialog.
		isRecurring?: boolean;
		saving?: boolean;
		error?: string;
		onSave: (payload: UpdateVisitInput) => void;
		onSaveFuture?: (payload: UpdateVisitInput) => void;
		onClose: () => void;
	} = $props();

	let title = $state('');
	let scheduleLater = $state(false);
	let anytime = $state(false);
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let instructions = $state('');
	let assigneeIds = $state<string[]>([]);
	let fieldError = $state('');

	// Re-read the visit into the form each time the dialog opens, never while it is open, so typing is never
	// overwritten by a background refetch of the same visit.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen && visit) {
			title = visit.title ?? '';
			scheduleLater = visit.visit_date === null;
			anytime = visit.visit_date !== null && !visit.start_time;
			when = {
				date: calendarDateFromString(visit.visit_date),
				startTime: timeFromString(visit.start_time),
				endTime: timeFromString(visit.end_time)
			};
			instructions = visit.instructions ?? '';
			assigneeIds = [...visit.assignee_ids];
			fieldError = '';
		}
		wasOpen = open;
	});

	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: open,
		staleTime: 5 * 60 * 1000
	}));
	const team = $derived<TeamMember[]>(teamQuery.data ?? []);

	function toggleAssignee(id: string, checked: boolean) {
		assigneeIds = checked ? [...assigneeIds, id] : assigneeIds.filter((entry) => entry !== id);
	}

	// The same shape rules the create form and the database enforce, checked here so a bad combination is a
	// message in the dialog rather than a raw constraint bounced back from the write.
	function collect(): UpdateVisitInput | null {
		const base = {
			title: title.trim() || null,
			instructions: instructions.trim() || null,
			assignee_ids: assigneeIds
		};
		if (scheduleLater) {
			return { ...base, visit_date: null, start_time: null, end_time: null, all_day: false };
		}
		const day = calendarDateToString(when.date);
		if (!day) {
			fieldError = 'Pick a day for this visit, or tick "Schedule later".';
			return null;
		}
		if (anytime) {
			return { ...base, visit_date: day, start_time: null, end_time: null, all_day: true };
		}
		const start = timeToString(when.startTime);
		const end = timeToString(when.endTime);
		if (end && !start) {
			fieldError = 'Set a start time before an end time.';
			return null;
		}
		if (start && end && end <= start) {
			fieldError = 'The end time has to come after the start time.';
			return null;
		}
		return {
			...base,
			visit_date: day,
			start_time: start || null,
			end_time: end || null,
			all_day: false
		};
	}

	function submit() {
		fieldError = '';
		const payload = collect();
		if (payload) onSave(payload);
	}

	// Same shape, but the section saves this visit and then opens "Apply to later visits". Undated visits have
	// no later visits to name, so the button is hidden for one and this path is never reached with a null date.
	function submitFuture() {
		fieldError = '';
		const payload = collect();
		if (payload) onSaveFuture?.(payload);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="Edit visit" {onClose}>
	<div class="visit-dialog">
		{#if error}<p class="visit-dialog__alert" role="alert">{error}</p>{/if}
		{#if fieldError}<p class="visit-dialog__alert" role="alert">{fieldError}</p>{/if}

		{#if isRecurring}
			<p class="visit-dialog__note">
				Changes here affect this visit only, unless you choose to update the later ones.
			</p>
		{/if}

		<Input
			id="visit-dialog-title"
			label="Visit title"
			placeholder={jobTitle.trim()
				? `Leave blank to use “${jobTitle.trim()}”`
				: 'Leave blank to use the job title'}
			bind:value={title}
			maxlength={160}
		/>

		<Checkbox
			id="visit-dialog-later"
			label="Schedule later"
			description="Keep this visit in the backlog without a date until you know it."
			bind:checked={scheduleLater}
		/>

		{#if !scheduleLater}
			<DateTimePicker
				id="visit-dialog-when"
				range
				showTime={!anytime}
				dateLabel="Day of the visit"
				timeLabel="Time"
				{locale}
				bind:value={when}
			/>
			<Checkbox
				id="visit-dialog-anytime"
				label="Anytime"
				description="Promise the day without promising an hour."
				checked={anytime}
				onchange={(checked) => {
					anytime = checked;
					if (checked) when = { ...when, startTime: undefined, endTime: undefined };
				}}
			/>
		{/if}

		<Textarea
			id="visit-dialog-instructions"
			label="Instructions for this visit"
			rows={3}
			maxlength={2000}
			bind:value={instructions}
		/>

		<fieldset class="visit-dialog__team">
			<legend class="visit-dialog__team-legend">
				<span aria-hidden="true">{@html usersIcon}</span> Assigned team
			</legend>
			{#if teamQuery.isPending}
				<p class="visit-dialog__hint">Loading your team…</p>
			{:else if team.length === 0}
				<p class="visit-dialog__hint">No team members to assign yet.</p>
			{:else}
				<div class="visit-dialog__team-list">
					{#each team as member (member.id)}
						<Checkbox
							id={`visit-dialog-assignee-${member.id}`}
							label={member.full_name ?? 'A team member'}
							checked={assigneeIds.includes(member.id)}
							onchange={(checked) => toggleAssignee(member.id, checked)}
						/>
					{/each}
				</div>
			{/if}
		</fieldset>

		<div class="visit-dialog__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			{#if isRecurring && onSaveFuture && !scheduleLater}
				<Button variant="secondary" onclick={submitFuture} loading={saving}>
					Save and update future visits
				</Button>
			{/if}
			<Button onclick={submit} loading={saving}>Save visit</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.visit-dialog {
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

		&__team {
			margin: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__team-legend {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
			padding: 0 var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__team-list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
