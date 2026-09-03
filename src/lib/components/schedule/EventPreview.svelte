<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
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
	<p class="event-preview__kind">Event</p>
	<p class="event-preview__title">{event.title.trim() || 'Event'}</p>

	<dl class="event-preview__facts">
		<dt>When</dt>
		<dd>{dayLabel} · {timeLabel}</dd>

		{#if event.description?.trim()}
			<dt>Details</dt>
			<dd>{event.description.trim()}</dd>
		{/if}
	</dl>

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
		gap: var(--space-slim);
	}

	.event-preview__kind {
		margin: 0;
		color: var(--color-event--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}

	.event-preview__title {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
	}

	.event-preview__facts {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		gap: var(--space-smaller) var(--space-slim);
		margin: 0;
		width: 100%;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
		}

		dd {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
			overflow-wrap: anywhere;
			white-space: pre-wrap;
		}
	}

	.event-preview__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
</style>
