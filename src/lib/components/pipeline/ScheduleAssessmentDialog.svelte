<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import {
		calendarDateToString,
		emptyDateTimePickerValue,
		timeToString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { DragWriteError } from '$lib/pipeline/api';

	// The one drag target that needs input before the move can run: dropping a card onto "Assessment
	// scheduled" has to say when. Mirrors `AssessmentBlock`'s own scheduled fields, minus instructions and
	// team -- the drag endpoint only ever writes a start and an end time. The caller owns the actual write
	// (it already knows the card and the target stage); this dialog only collects the time and shows
	// whatever comes back from it.
	let {
		open,
		title,
		onConfirm,
		onClose
	}: {
		open: boolean;
		title: string;
		onConfirm: (startsAt: string, endsAt: string) => Promise<void>;
		onClose: () => void;
	} = $props();

	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function isoFrom(day: string, time: string) {
		const parsed = new Date(`${day}T${time}`);
		return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
	}

	async function save() {
		if (saving) return;
		formError = '';
		fieldErrors = {};

		const day = calendarDateToString(when.date);
		const startTime = timeToString(when.startTime);
		const endTime = timeToString(when.endTime);
		if (!day || !startTime || !endTime) {
			formError = 'Pick a day and a start and end time for the visit.';
			return;
		}

		const startsAt = isoFrom(day, startTime);
		const endsAt = isoFrom(day, endTime);
		if (!startsAt || !endsAt) {
			formError = 'That date and time could not be read. Try picking them again.';
			return;
		}
		if (Date.parse(endsAt) <= Date.parse(startsAt)) {
			formError = 'The end time has to come after the start time.';
			return;
		}

		saving = true;
		try {
			await onConfirm(startsAt, endsAt);
		} catch (thrown) {
			if (thrown instanceof DragWriteError) {
				fieldErrors = thrown.fieldErrors;
				formError =
					fieldErrors.form ?? (Object.keys(fieldErrors).length === 0 ? thrown.message : '');
			} else {
				formError = thrown instanceof Error ? thrown.message : 'That visit could not be scheduled.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} {title} onClose={saving ? () => {} : onClose}>
	<div class="schedule-dialog">
		<DateTimePicker
			id="schedule-dialog-when"
			range
			dateLabel="Day of the visit"
			timeLabel="Time"
			bind:value={when}
			invalid={Boolean(fieldErrors.starts_at || fieldErrors.ends_at)}
			errorMessage={fieldErrors.starts_at || fieldErrors.ends_at}
		/>

		{#if formError}<p class="schedule-dialog__error" role="alert">{formError}</p>{/if}

		<div class="schedule-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={() => void save()}>Schedule</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.schedule-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

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
