<script lang="ts">
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { Time } from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeToMinutes,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		browserTimeZone,
		refreshCalendar,
		zonedInstant,
		zonedPlace,
		type CalendarEntry
	} from '$lib/jafar/calendar';

	// Jafar business management C2: a one-off Busy block -- time Jafar is not free for calls ("Dentist"). It has
	// no reminders and no business. E1's public booking will hide this time from visitors.
	let {
		entry = null,
		seed = null,
		zone,
		onClose
	}: {
		/** The block being changed, or null for a new one. */
		entry?: CalendarEntry | null;
		seed?: { day: string; start: number; end: number } | null;
		zone: string;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	function timeOf(minutes: number) {
		return new Time(Math.floor(minutes / 60) % 24, minutes % 60);
	}

	function startingValue(): { title: string; when: DateTimePickerValue } {
		if (entry) {
			const start = zonedPlace(entry.starts_at, zone);
			const end = zonedPlace(entry.ends_at, zone);
			return {
				title: entry.title ?? '',
				when: {
					date: calendarDateFromString(start.day),
					startTime: timeOf(start.minutes),
					endTime: timeOf(end.day === start.day ? end.minutes : 23 * 60 + 59)
				}
			};
		}
		const place = seed ?? {
			day: zonedPlace(new Date().toISOString(), zone).day,
			start: 12 * 60,
			end: 13 * 60
		};
		return {
			title: '',
			when: {
				date: calendarDateFromString(place.day),
				startTime: timeOf(place.start),
				endTime: timeOf(Math.min(place.end, 23 * 60 + 59))
			}
		};
	}

	const start = untrack(startingValue);
	let title = $state(start.title);
	let when = $state<DateTimePickerValue>(start.when);
	let error = $state('');
	let saving = $state(false);
	let removing = $state(false);

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		error = '';
		const day = calendarDateToString(when.date);
		const from = timeToMinutes(when.startTime);
		const to = timeToMinutes(when.endTime);
		if (!day || from === undefined || to === undefined) {
			error = 'Choose the day and when it starts and ends.';
			return;
		}
		if (to <= from) {
			error = 'End after it starts.';
			return;
		}
		const span = { starts_at: zonedInstant(day, from, zone), ends_at: zonedInstant(day, to, zone) };
		saving = true;
		const result = entry
			? await sendLeadWrite(
					`/api/jafar/calendar/entries/${encodeURIComponent(entry.id)}`,
					'PATCH',
					{
						action: 'busy',
						...span,
						title: title.trim() || null
					}
				)
			: await sendLeadWrite('/api/jafar/calendar/entries', 'POST', {
					kind: 'busy',
					...span,
					title: title.trim() || null,
					time_zone: browserTimeZone()
				});
		if (!result.ok) {
			saving = false;
			error = result.error;
			return;
		}
		await refreshCalendar(queryClient);
		saving = false;
		toast.success(entry ? 'Busy time saved' : 'Busy time added');
		onClose();
	}

	async function remove() {
		if (!entry || removing) return;
		removing = true;
		const result = await sendLeadWrite(
			`/api/jafar/calendar/entries/${encodeURIComponent(entry.id)}`,
			'DELETE'
		);
		if (!result.ok) {
			removing = false;
			error = result.error;
			return;
		}
		await refreshCalendar(queryClient);
		removing = false;
		toast.success('Busy time removed');
		onClose();
	}
</script>

<Dialog
	open={true}
	title={entry ? 'Busy time' : 'Block out busy time'}
	size="small"
	initialFocusId="busy-title"
	{onClose}
>
	<form class="busy-form" onsubmit={save} novalidate>
		<p class="busy-form__hint">Time you are not free for calls. Only you see the label.</p>
		<Input
			id="busy-title"
			label="Label (optional)"
			placeholder="Busy"
			maxlength={200}
			autocomplete="off"
			bind:value={title}
		/>
		<DateTimePicker id="busy-when" range dateLabel="Day" timeLabel="Time" bind:value={when} />

		{#if error}<p class="busy-form__error" role="alert">{error}</p>{/if}

		<div class="busy-form__actions">
			{#if entry}
				<Button variant="tertiary" variation="destructive" onclick={remove} loading={removing}>
					Remove
				</Button>
			{/if}
			<span class="busy-form__spacer"></span>
			<Button variant="secondary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button type="submit" loading={saving}>Save</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.busy-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__spacer {
			flex: 1;
		}
	}
</style>
