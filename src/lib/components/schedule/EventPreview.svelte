<script lang="ts">
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import SchedulePreviewFacts from '$lib/components/schedule/SchedulePreviewFacts.svelte';
	import { visitShape } from '$lib/schedule/status';
	import { clockLabel } from '$lib/schedule/labels';
	import type { EventItem } from '$lib/schedule/items';

	// What an event card says when you select it. An event is Schedule's own, so unlike an assessment the
	// calendar edits it in place: this preview reads it and offers completion, Edit
	// and Delete -- but only to a reader who may change the schedule. Without that authority it is read-only,
	// exactly as the visit preview hides its own actions.

	let {
		event,
		dayLabel,
		canSchedule = false,
		completing = false,
		completionError = '',
		oncomplete,
		onedit,
		ondelete
	}: {
		event: EventItem;
		/** The event's date already in words, so every surface says the date the same way. */
		dayLabel: string;
		canSchedule?: boolean;
		completing?: boolean;
		completionError?: string;
		oncomplete: () => void;
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

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="event-preview">
	{#if event.completed_at}<StatusBadge status="success" size="small">Completed</StatusBadge>{/if}
	{#if completionError}<p class="event-preview__error" role="alert">{completionError}</p>{/if}
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
			{#if !event.completed_at}<Button size="small" fullWidth loading={completing} onclick={oncomplete}>{@html checkIcon}Mark complete</Button>{/if}
			<Button variant="secondary" size="small" onclick={onedit} disabled={completing}>{@html pencilIcon}Edit</Button>
			<Button variant="secondary" variation="destructive" size="small" onclick={ondelete} disabled={completing}>{@html trashIcon}Delete</Button>
		</div>
	{/if}
</div>
<!-- eslint-enable svelte/no-at-html-tags -->

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
		
	}
	.event-preview__error {color: var(--color-critical--onSurface); font-size: var(--typography--fontSize-label);}
</style>
