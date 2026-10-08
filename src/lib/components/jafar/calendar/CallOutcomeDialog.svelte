<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate, Time } from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import RadioGroup from '$lib/components/ui/RadioGroup.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString, timeToMinutes } from '$lib/components/ui/date-time';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		calendarEntryKey,
		fetchCalendarEntry,
		refreshCalendar,
		zonedInstant,
		zonedPlace,
		type CallOutcome
	} from '$lib/jafar/calendar';

	// Jafar business management C2: "How did it go?" for a call -- Held, They didn't show, or Cancelled -- as
	// HubSpot's and Pipedrive's call outcomes. When the call was the business's next action, the next step is asked
	// here too, so the business is never quietly left without one: They didn't show suggests "Reschedule" today.
	// Opened from a passed call, or with `cancelling` from Cancel call on an upcoming one.
	let {
		entryId,
		zone,
		cancelling = false,
		onClose
	}: {
		entryId: string;
		zone: string;
		/** The call has not happened yet: the only outcome is Cancelled. */
		cancelling?: boolean;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const entryQuery = createQuery(() => ({
		queryKey: calendarEntryKey(entryId),
		queryFn: () => fetchCalendarEntry(entryId)
	}));
	const entry = $derived(entryQuery.data);

	const OPTIONS = [
		{ value: 'held', label: 'Held' },
		{ value: 'no_show', label: "They didn't show" },
		{ value: 'cancelled', label: 'Cancelled' }
	];

	const todayPlace = zonedPlace(
		new Date().toISOString(),
		untrack(() => zone)
	);
	const todayDate = calendarDateFromString(todayPlace.day) as CalendarDate;

	let outcome = $state<CallOutcome | ''>(untrack(() => (cancelling ? 'cancelled' : '')));
	let nextText = $state('');
	let nextDay = $state<CalendarDate | undefined>(undefined);
	let nextTime = $state<Time | undefined>(undefined);
	let touchedNext = false;
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);

	// They didn't show: suggest rescheduling today, until the step has been typed over.
	function choose(value: string) {
		outcome = value as CallOutcome;
		if (touchedNext) return;
		if (value === 'no_show') {
			nextText = 'Reschedule';
			nextDay = todayDate;
		} else {
			nextText = '';
			nextDay = undefined;
		}
	}

	const asksNext = $derived(entry?.is_next_action === true);

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (saving || !entry) return;
		formError = '';
		fieldErrors = {};
		if (!outcome) {
			fieldErrors = { outcome: 'Choose how it went.' };
			return;
		}
		const hasNext = asksNext && (nextText.trim() || nextDay);
		if (hasNext && !nextText.trim()) fieldErrors['next_action.text'] = 'Say what the next step is.';
		if (hasNext && !nextDay) fieldErrors['next_action.due_on'] = 'Choose when it is due.';
		if (Object.keys(fieldErrors).length) return;

		const minutes = timeToMinutes(nextTime);
		saving = true;
		const result = await sendLeadWrite(
			`/api/jafar/calendar/entries/${encodeURIComponent(entryId)}`,
			'PATCH',
			{
				action: 'close',
				outcome,
				next_action:
					hasNext && nextDay
						? {
								text: nextText.trim(),
								due_on: nextDay.toString(),
								due_at:
									minutes === undefined ? null : zonedInstant(nextDay.toString(), minutes, zone)
							}
						: null
			}
		);
		if (!result.ok) {
			saving = false;
			fieldErrors = result.fieldErrors;
			formError = result.error;
			return;
		}
		await refreshCalendar(queryClient);
		saving = false;
		toast.success(outcome === 'cancelled' ? 'Call cancelled' : 'Outcome saved');
		onClose();
	}

	const callWords = $derived.by(() => {
		if (!entry) return '';
		const format = new Intl.DateTimeFormat(undefined, {
			timeZone: zone,
			weekday: 'short',
			day: 'numeric',
			month: 'short',
			hour: 'numeric',
			minute: '2-digit'
		});
		return `${entry.title ?? `Call with ${entry.business_name}`} · ${format.format(new Date(entry.starts_at))}`;
	});
</script>

<Dialog
	open={true}
	title={cancelling ? 'Cancel this call?' : 'How did it go?'}
	size="small"
	{onClose}
>
	{#if !entry}
		{#if entryQuery.isError}
			<p class="call-outcome__error" role="alert">{entryQuery.error.message}</p>
		{:else}
			<LoadingSkeleton variant="card" rows={2} label="Loading the call" />
		{/if}
	{:else}
		<form class="call-outcome" onsubmit={save} novalidate>
			<p class="call-outcome__call">{callWords}</p>

			{#if !cancelling}
				<RadioGroup label="Outcome" options={OPTIONS} value={outcome} onchange={choose} />
				{#if fieldErrors.outcome}
					<p class="call-outcome__error" role="alert">{fieldErrors.outcome}</p>
				{/if}
			{/if}

			{#if asksNext && outcome}
				<fieldset class="call-outcome__next">
					<legend>What's next with {entry.business_name}?</legend>
					<p class="call-outcome__hint">Leave it empty if there is no next step yet.</p>
					<Input
						id="call-outcome-next"
						label="Next step"
						placeholder="e.g. Send pricing"
						maxlength={200}
						autocomplete="off"
						invalid={Boolean(fieldErrors['next_action.text'])}
						errorMessage={fieldErrors['next_action.text'] ?? ''}
						bind:value={nextText}
						oninput={() => (touchedNext = true)}
					/>
					<div class="call-outcome__when">
						<CalendarPicker
							id="call-outcome-day"
							label="Due"
							minValue={todayDate}
							invalid={Boolean(fieldErrors['next_action.due_on'])}
							errorMessage={fieldErrors['next_action.due_on'] ?? ''}
							bind:value={nextDay}
							onchange={() => (touchedNext = true)}
						/>
						<TimePickerField id="call-outcome-time" label="Time (optional)" bind:value={nextTime} />
					</div>
				</fieldset>
			{/if}

			{#if formError}<p class="call-outcome__error" role="alert">{formError}</p>{/if}

			<div class="call-outcome__actions">
				<Button variant="secondary" onclick={onClose} disabled={saving}>
					{cancelling ? 'Keep the call' : 'Not now'}
				</Button>
				<Button
					type="submit"
					variation={outcome === 'cancelled' ? 'destructive' : 'work'}
					loading={saving}
				>
					{cancelling ? 'Cancel call' : 'Save'}
				</Button>
			</div>
		</form>
	{/if}
</Dialog>

<style lang="scss">
	.call-outcome {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__call {
			margin: 0;
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__next {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);

			legend {
				padding: 0 var(--space-smaller);
				font-weight: 600;
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__when {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
			gap: var(--space-small);
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
