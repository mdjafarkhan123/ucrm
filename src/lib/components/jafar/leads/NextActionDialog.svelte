<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate, Time, today, getLocalTimeZone } from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import ReminderPicker from '$lib/components/jafar/calendar/ReminderPicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString, timeToMinutes } from '$lib/components/ui/date-time';
	import { refreshLead, sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		browserTimeZone,
		calendarPreferencesKey,
		fetchCalendarPreferences,
		refreshCalendar,
		zonedInstant,
		zonedPlace,
		type ReminderRule
	} from '$lib/jafar/calendar';

	// Jafar business management B2: a Lead's next action -- one dated step. `set` adds or changes it; `done`
	// records the current one as done and asks for the next, as Pipedrive does, so a Lead being worked is not
	// left without a step. Leaving the next one empty is allowed: the Leads list then flags it. C2: a time is
	// optional, and the reminders follow My preferences unless changed here -- "days before at" for a day, "so long
	// before" once there is a time.
	let {
		leadId,
		mode,
		current,
		onClose
	}: {
		leadId: string;
		mode: 'set' | 'done';
		current: {
			text: string;
			due_on: string;
			due_at?: string | null;
			reminders?: ReminderRule[] | null;
		} | null;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const preferencesQuery = createQuery(() => ({
		queryKey: calendarPreferencesKey,
		queryFn: fetchCalendarPreferences,
		staleTime: 5 * 60_000
	}));
	const zone = $derived(preferencesQuery.data?.time_zone ?? browserTimeZone());

	const startText = untrack(() => (mode === 'set' ? (current?.text ?? '') : ''));
	const startDue = untrack(() =>
		mode === 'set' ? calendarDateFromString(current?.due_on) : undefined
	);
	const startTime = untrack(() => {
		if (mode !== 'set' || !current?.due_at) return undefined;
		const minutes = zonedPlace(
			current.due_at,
			preferencesQuery.data?.time_zone ?? browserTimeZone()
		).minutes;
		return new Time(Math.floor(minutes / 60), minutes % 60);
	});
	let text = $state(startText);
	let dueOn = $state<CalendarDate | undefined>(startDue);
	let dueTime = $state<Time | undefined>(startTime);
	let reminders = $state<ReminderRule[] | null>(
		untrack(() => (mode === 'set' ? (current?.reminders ?? null) : null))
	);
	const timed = $derived(dueTime !== undefined);
	const defaults = $derived(
		timed
			? (preferencesQuery.data?.reminder_defaults.follow_up_timed ?? [])
			: (preferencesQuery.data?.reminder_defaults.follow_up_day ?? [])
	);
	// Adding or removing the time changes what a reminder means, so chosen ones of the other kind go.
	function changeTime(next: Time | undefined) {
		const nowTimed = next !== undefined;
		if (reminders?.some((rule) => 'minutes_before' in rule !== nowTimed)) reminders = null;
	}
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);

	const todayDate = today(getLocalTimeZone());
	const quickDates = [
		{ label: 'Tomorrow', days: 1 },
		{ label: 'In 3 days', days: 3 },
		{ label: 'Next week', days: 7 }
	];

	const title = $derived(
		mode === 'done' ? 'Mark next action done' : current ? 'Change next action' : 'Set next action'
	);

	function localErrors() {
		const errors: Record<string, string> = {};
		const hasText = Boolean(text.trim());
		if (mode === 'set' || hasText || dueOn) {
			if (!hasText) errors['next_action.text'] = 'Say what the next action is.';
			if (!dueOn) errors['next_action.due_on'] = 'Choose when the next action is due.';
		}
		return errors;
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		formError = '';
		fieldErrors = localErrors();
		if (Object.keys(fieldErrors).length) return;

		const minutes = timeToMinutes(dueTime);
		const hasNext = Boolean(text.trim() && dueOn);
		const timing = {
			due_at:
				hasNext && dueOn && minutes !== undefined
					? zonedInstant(dueOn.toString(), minutes, zone)
					: null,
			reminders: hasNext ? reminders : null
		};
		const nextAction =
			mode === 'set'
				? { mode: 'set', text: text.trim(), due_on: dueOn?.toString(), ...timing }
				: {
						mode: 'done',
						text: text.trim() || null,
						due_on: text.trim() ? (dueOn?.toString() ?? null) : null,
						...timing
					};
		saving = true;
		const result = await sendLeadWrite(`/api/jafar/leads/${encodeURIComponent(leadId)}`, 'PATCH', {
			next_action: nextAction
		});
		if (!result.ok) {
			saving = false;
			fieldErrors = result.fieldErrors;
			formError = result.error;
			return;
		}
		// Still saving while the lists reload, so the button can't be pressed twice and the old step never flashes back.
		await Promise.all([refreshLead(queryClient, leadId), refreshCalendar(queryClient)]);
		saving = false;
		toast.success(mode === 'done' ? 'Marked done' : 'Next action saved');
		onClose();
	}
</script>

<Dialog open={true} {title} size="small" initialFocusId="next-action-text" {onClose}>
	<form class="next-action-form" onsubmit={submit} novalidate>
		{#if mode === 'done' && current}
			<p class="next-action-form__done">
				<span>Done:</span>
				<strong>{current.text}</strong>
			</p>
			<p class="next-action-form__lead">
				What is the next step? Leave it empty if there is none yet.
			</p>
		{/if}

		<Input
			id="next-action-text"
			label={mode === 'done' ? 'Next action (optional)' : 'Next action'}
			placeholder="e.g. Call back about pricing"
			maxlength={200}
			required={mode === 'set'}
			autocomplete="off"
			invalid={Boolean(fieldErrors['next_action.text'])}
			errorMessage={fieldErrors['next_action.text'] ?? ''}
			bind:value={text}
		/>

		<div class="next-action-form__due">
			<CalendarPicker
				id="next-action-due"
				label="Due"
				required={mode === 'set'}
				minValue={todayDate}
				invalid={Boolean(fieldErrors['next_action.due_on'])}
				errorMessage={fieldErrors['next_action.due_on'] ?? ''}
				bind:value={dueOn}
			/>
			<div class="next-action-form__quick" role="group" aria-label="Quick dates">
				{#each quickDates as quick (quick.days)}
					<button
						type="button"
						class="next-action-form__chip"
						onclick={() => (dueOn = todayDate.add({ days: quick.days }))}>{quick.label}</button
					>
				{/each}
			</div>
		</div>

		<TimePickerField
			id="next-action-time"
			label="Time (optional)"
			bind:value={dueTime}
			onchange={changeTime}
		/>

		{#if text.trim() || mode === 'set'}
			<ReminderPicker id="next-action-reminders" {timed} {defaults} bind:value={reminders} />
			{#if fieldErrors['next_action.reminders']}
				<p class="next-action-form__error" role="alert">{fieldErrors['next_action.reminders']}</p>
			{/if}
		{/if}

		{#if formError && !fieldErrors['next_action.text'] && !fieldErrors['next_action.due_on'] && !fieldErrors['next_action.reminders']}
			<p class="next-action-form__error" role="alert">{formError}</p>
		{/if}

		<div class="next-action-form__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button variant="primary" type="submit" loading={saving}>
				{mode === 'done' ? (text.trim() ? 'Mark done and save next' : 'Mark done') : 'Save'}
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.next-action-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__done {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
			overflow-wrap: anywhere;
		}

		&__lead {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__due {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__quick {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__chip {
			padding: var(--space-smaller) var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-text);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			cursor: pointer;
			transition:
				background-color var(--timing-quick),
				border-color var(--timing-quick);

			&:hover {
				border-color: var(--color-border--interactive, var(--color-interactive));
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
