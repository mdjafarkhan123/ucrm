<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { durationLabel } from '$lib/time-clock/api';
	import {
		approvalMessage,
		approvalPreviewKey,
		approveTimesheets,
		fetchApprovalPreview,
		type ApprovalError,
		type ApprovalRunningTimer
	} from '$lib/time-clock/approval';
	import { refreshAfterCorrection } from '$lib/time-clock/corrections';
	import { clockTime, runningPurpose } from '$lib/time-clock/timesheets';

	// Approve timesheets (plan § Weekly approval), as Jobber's Approve Timesheets works: choose a day and the
	// people, and every stopped entry of theirs up to and including that day is approved. Approved hours are
	// locked for people who change only their own; managers can still change them. Running timers are never
	// approved and are listed so they can be stopped first. There is no undo.
	let {
		open,
		initialCutoff,
		today,
		timezone,
		onClose
	}: {
		open: boolean;
		/** The day the dialog starts on: the end of the window being looked at, never after today. */
		initialCutoff: string;
		today: string;
		timezone: string;
		onClose: () => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();

	let cutoff = $state('');
	// People left out by hand. Everyone else waiting is included, also after the day changes.
	let leftOut = $state<string[]>([]);
	let saving = $state(false);
	let error = $state('');

	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			cutoff = initialCutoff;
			leftOut = [];
			saving = false;
			error = '';
		}
		wasOpen = open;
	});

	const previewQuery = createQuery(() => ({
		queryKey: approvalPreviewKey(cutoff || initialCutoff),
		queryFn: () => fetchApprovalPreview(cutoff || initialCutoff),
		enabled: open && Boolean(cutoff || initialCutoff),
		staleTime: 15_000
	}));

	const people = $derived(previewQuery.data?.people ?? []);
	const running = $derived(previewQuery.data?.running ?? []);
	const chosen = $derived(people.filter((person) => !leftOut.includes(person.user_id)));
	const chosenEntries = $derived(chosen.reduce((sum, person) => sum + person.entry_count, 0));
	const chosenMinutes = $derived(chosen.reduce((sum, person) => sum + person.minutes, 0));
	const allChosen = $derived(people.length > 0 && chosen.length === people.length);

	function choose(userId: string, include: boolean) {
		leftOut = include ? leftOut.filter((id) => id !== userId) : [...leftOut, userId];
	}

	function chooseAll(include: boolean) {
		leftOut = include ? [] : people.map((person) => person.user_id);
	}

	function shortDay(day: string) {
		return formatCalendarDay(day, { weekday: 'short', month: 'short', day: 'numeric' });
	}

	function personSummary(entries: number, minutes: number, firstDay: string) {
		const count = entries === 1 ? '1 entry' : `${entries} entries`;
		return `${count} · ${durationLabel(minutes)} · from ${shortDay(firstDay)}`;
	}

	function runningLine(timer: ApprovalRunningTimer) {
		const what = runningPurpose(timer);
		return `${timer.name ?? 'A team member'}: ${what}, since ${shortDay(timer.started_on)} at ${clockTime(
			timer.started_at,
			timezone
		)}`;
	}

	async function approve() {
		if (saving || chosen.length === 0) return;
		error = '';
		saving = true;
		try {
			const result = await approveTimesheets(
				cutoff,
				chosen.map((person) => person.user_id)
			);
			await refreshAfterCorrection(queryClient);
			toast.success(approvalMessage(result));
			onClose();
		} catch (cause) {
			error = (cause as ApprovalError).message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	open={open && Boolean(initialCutoff)}
	title="Approve timesheets"
	onClose={() => !saving && onClose()}
>
	<form
		class="approve-timesheets"
		onsubmit={(event) => {
			event.preventDefault();
			void approve();
		}}
	>
		{#if error}<p class="approve-timesheets__alert" role="alert">{error}</p>{/if}

		<p class="approve-timesheets__intro">
			Every stopped entry up to and including the day is approved. Approved hours are locked for
			people who change only their own; you can still change them, and each change is kept in the
			entry’s history.
		</p>

		<CalendarPicker
			id="approve-up-to"
			label="Approve up to and including"
			class="approve-timesheets__day"
			value={calendarDateFromString(cutoff || initialCutoff)}
			maxValue={calendarDateFromString(today)}
			onchange={(value) => {
				const day = calendarDateToString(value);
				if (day && day <= today) cutoff = day;
			}}
		/>

		<fieldset class="approve-timesheets__people" aria-busy={previewQuery.isFetching}>
			<legend class="approve-timesheets__legend">Waiting for approval</legend>
			{#if previewQuery.isPending}
				<p class="approve-timesheets__status" role="status">Loading what is waiting…</p>
			{:else if previewQuery.isError}
				<p class="approve-timesheets__status approve-timesheets__status--error" role="alert">
					{previewQuery.error.message}
					<Button
						variant="quiet"
						size="small"
						loading={previewQuery.isFetching}
						onclick={() => void previewQuery.refetch()}>Try again</Button
					>
				</p>
			{:else if people.length === 0}
				<p class="approve-timesheets__status">
					Nothing is waiting. Every stopped entry up to {shortDay(cutoff || initialCutoff)} is already
					approved.
				</p>
			{:else}
				{#if people.length > 1}
					<div class="approve-timesheets__all">
						<Checkbox
							id="approve-everyone"
							label={`Everyone (${people.length})`}
							checked={allChosen}
							indeterminate={chosen.length > 0 && !allChosen}
							onchange={chooseAll}
						/>
					</div>
				{/if}
				<ul class="approve-timesheets__list">
					{#each people as person (person.user_id)}
						<li class="approve-timesheets__person">
							<Checkbox
								id={`approve-${person.user_id}`}
								label={person.is_me
									? `${person.name ?? 'You'} (you)`
									: (person.name ?? 'A team member')}
								description={personSummary(person.entry_count, person.minutes, person.first_day)}
								checked={!leftOut.includes(person.user_id)}
								onchange={(include) => choose(person.user_id, include)}
							/>
						</li>
					{/each}
				</ul>
			{/if}
		</fieldset>

		{#if running.length > 0}
			<div class="approve-timesheets__running" role="note">
				<p>
					<strong>Still running, so not approved.</strong> Stop {running.length === 1
						? 'this timer'
						: 'these timers'} from the person’s row first, then approve again.
				</p>
				<ul>
					{#each running as timer (timer.user_id)}
						<li>{runningLine(timer)}</li>
					{/each}
				</ul>
			</div>
		{/if}

		<div class="approve-timesheets__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button
				variant="primary"
				type="submit"
				loading={saving}
				disabled={chosen.length === 0 || previewQuery.isFetching}
			>
				{chosenEntries === 0
					? 'Approve'
					: `Approve ${chosenEntries === 1 ? '1 entry' : `${chosenEntries} entries`} · ${durationLabel(chosenMinutes)}`}
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.approve-timesheets {
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

		&__intro {
			margin: 0;
			color: var(--color-text);
		}

		:global(.approve-timesheets__day) {
			max-width: 16rem;
		}

		&__people {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			min-width: 0;
			margin: 0;
			padding: 0;
			border: 0;
		}

		&__legend {
			margin-bottom: var(--space-small);
			padding: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__status {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			&--error {
				color: var(--color-critical--onSurface);
			}
		}

		&__retry {
			margin-left: var(--space-smaller);
			padding: 0;
			border: 0;
			border-radius: var(--radius-small);
			background: none;
			color: var(--color-interactive);
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__all {
			padding: 0 var(--space-base);
		}

		&__list {
			display: flex;
			flex-direction: column;
			max-height: 18rem;
			margin: 0;
			padding: 0;
			overflow-y: auto;
			list-style: none;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__person {
			padding: var(--space-small) var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__running {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);

			p {
				margin: 0;
			}

			ul {
				margin: var(--space-smaller) 0 0;
				padding-left: var(--space-large);
			}
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
