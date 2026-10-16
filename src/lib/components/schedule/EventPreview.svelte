<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import SchedulePreviewFacts from '$lib/components/schedule/SchedulePreviewFacts.svelte';
	import { visitShape } from '$lib/schedule/status';
	import { clockLabel } from '$lib/schedule/labels';
	import type { EventItem } from '$lib/schedule/items';

	// What an event card says when you select it. An event is Schedule's own, so unlike an assessment the
	// calendar edits it in place: this preview reads it and offers the two changes the contract allows -- Edit
	// and Delete -- but only to a reader who may change the schedule. Without that authority it is read-only,
	// exactly as the visit preview hides its own actions.

	let {
		event,
		dayLabel,
		canSchedule = false,
		onedit,
		ondelete
	}: {
		event: EventItem;
		/** The event's date already in words, so every surface says the date the same way. */
		dayLabel: string;
		canSchedule?: boolean;
		onedit: () => void;
		ondelete: () => void;
	} = $props();

	const timeLabel = $derived.by(() => {
		if (visitShape(event) === 'anytime') return 'Anytime';
		const start = clockLabel(event.start_time);
		if (!start) return 'Anytime';
		const end = clockLabel(event.end_time);
		return end ? `${start} – ${end}` : start;
	});
</script>

<div class="event-preview">
	<SchedulePreviewFacts
		facts={[
			{ kind: 'when', label: 'When', value: `${dayLabel} · ${timeLabel}` },
			...(event.description?.trim()
				? [{ kind: 'details' as const, label: 'Details', value: event.description.trim() }]
				: [])
		]}
	/>

	{#if canSchedule}
		<div class="event-preview__actions">
			<Button variant="secondary" size="small" onclick={onedit}>Edit</Button>
			<Button variant="tertiary" size="small" onclick={ondelete}>Delete</Button>
		</div>
	{/if}
</div>

<style lang="scss">
	.event-preview {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
		min-width: 260px;
	}

	.event-preview__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		width: 100%;
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
