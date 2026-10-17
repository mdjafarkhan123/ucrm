<script lang="ts">
	import { visitShape } from '$lib/schedule/status';
	import { clockLabel } from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { EventItem } from '$lib/schedule/items';
	import calendarEventIcon from '@tabler/icons/outline/calendar-event.svg?raw';

	// One Schedule-owned event, drawn at whatever size the calendar could give it.
	//
	// An event is the lightest item there is: it has no client, no crew and no property, so the card carries
	// only its time and its title, with a calendar marker that says what it is. It never drags or resizes --
	// editing is a deliberate action from its own popover.

	let {
		event,
		density,
		selected = false,
		onselect
	}: {
		event: EventItem;
		density: CardDensity;
		selected?: boolean;
		/** The element is handed back so the page can anchor the preview to this exact card. */
		onselect: (event: EventItem, element: HTMLElement) => void;
	} = $props();

	const timeLabel = $derived.by(() => {
		if (visitShape(event) === 'anytime') return 'Anytime';
		const start = clockLabel(event.start_time);
		if (!start) return 'Anytime';
		const end = clockLabel(event.end_time);
		return end ? `${start} – ${end}` : start;
	});
	const timed = $derived(visitShape(event) !== 'anytime' && Boolean(clockLabel(event.start_time)));
	const startLabel = $derived(clockLabel(event.start_time) ?? '');

	const titleLabel = $derived(event.title.trim() || 'Event');

	const summary = $derived(['Event', timeLabel, titleLabel].filter(Boolean).join(', '));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class="event-card event-card--{density}"
	class:event-card--selected={selected}
	aria-label={summary}
	aria-pressed={selected}
	title={summary}
	onclick={(domEvent) => onselect(event, domEvent.currentTarget)}
>
	{#if density === 'standard'}
		<span class="event-card__time">
			<span class="event-card__marker" aria-hidden="true">{@html calendarEventIcon}</span>
			{timeLabel}
		</span>
		<span class="event-card__title event-card__title--block">{titleLabel}</span>
	{:else}
		<span class="event-card__marker" aria-hidden="true">{@html calendarEventIcon}</span>
		{#if timed}<span class="event-card__time">{startLabel}</span>{/if}
		<span class="event-card__title">{titleLabel}</span>
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// An event blocks time for the whole team -- a meeting, a training day, a holiday. It is a quiet pill on
	// the calendar's own tint rather than a coloured card, so it never competes with work that has a status.
	.event-card {
		display: flex;
		align-items: center;
		gap: 6px;
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: 0 var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid var(--color-surface--background--subtle);
		border-radius: var(--radius-base);
		background-color: var(--color-surface--background--subtle);
		color: var(--color-text);
		font-family: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--background--subtle--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.event-card--standard {
		flex-direction: column;
		align-items: flex-start;
		justify-content: flex-start;
		gap: var(--space-smallest);
		padding: 7px var(--space-small) var(--space-small) 9px;
	}

	.event-card--selected {
		box-shadow: var(--shadow-focus);
	}

	.event-card__marker {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}

	.event-card__time {
		display: inline-flex;
		flex-shrink: 0;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 600;
		line-height: 1.3;
		white-space: nowrap;
	}

	.event-card__title {
		min-width: 0;
		overflow: hidden;
		color: var(--color-heading);
		font-size: 12px;
		font-weight: 600;
		line-height: 1.25;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.event-card__title--block {
		white-space: normal;
	}
</style>
