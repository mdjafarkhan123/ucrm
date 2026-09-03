<script lang="ts">
	import { visitShape } from '$lib/schedule/status';
	import { clockLabel } from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { EventItem } from '$lib/schedule/items';
	import calendarEventIcon from '@tabler/icons/outline/calendar-event.svg?raw';

	// One Schedule-owned event, drawn at whatever size the calendar could give it.
	//
	// It mirrors the visit and assessment cards' shape so a day reads as one calendar, but an event is the
	// lightest item there is: it has no client, no crew and no property, so the card carries only its time and
	// its title. It wears the Event accent and, where there is room, a marker and an "Event" tag both say what
	// it is, so colour alone never carries the difference. It never drags or resizes -- editing is a
	// deliberate action from its own popover.

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
	const startLabel = $derived(
		visitShape(event) === 'anytime' ? 'Anytime' : (clockLabel(event.start_time) ?? 'Anytime')
	);

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
	<span class="event-card__accent" aria-hidden="true"></span>

	{#if density === 'micro'}
		<span class="event-card__line">
			<span class="event-card__marker" aria-hidden="true">{@html calendarEventIcon}</span>
			<span class="event-card__time">{startLabel}</span>
			<span class="event-card__title">{titleLabel}</span>
		</span>
	{:else}
		<span class="event-card__time">
			<span class="event-card__marker" aria-hidden="true">{@html calendarEventIcon}</span>
			{density === 'standard' ? timeLabel : startLabel}
		</span>
		<span class="event-card__title">{titleLabel}</span>

		{#if density === 'standard'}
			<span class="event-card__foot">
				<span class="event-card__tag">Event</span>
			</span>
		{/if}
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.event-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: var(--space-smaller) var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		background-color: var(--color-surface);
		color: var(--color-text);
		font-family: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.event-card__accent {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: var(--space-smaller);
		// The Event accent, so an event reads as a different kind of block from a job visit at a glance.
		background-color: var(--color-event);
	}

	.event-card--selected {
		background-color: var(--color-surface--active);
		box-shadow: var(--shadow-focus);
	}

	.event-card__line {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.event-card__marker {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--color-event--onSurface);

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.event-card__time {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		white-space: nowrap;
	}

	.event-card__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.event-card__foot {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: auto;
		min-width: 0;
	}

	.event-card__tag {
		flex-shrink: 0;
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-small);
		background-color: var(--color-event--surface);
		color: var(--color-event--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-loose);
		white-space: nowrap;
	}

	.event-card--micro {
		justify-content: center;
		padding: 0 var(--space-smaller) 0 var(--space-small);

		.event-card__time {
			flex-shrink: 0;
		}

		.event-card__title {
			flex: 1 1 auto;
			min-width: 0;
			color: var(--color-text);
			font-weight: 500;
		}
	}
</style>
