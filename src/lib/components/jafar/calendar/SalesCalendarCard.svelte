<script lang="ts">
	import type { CardDensity } from '$lib/schedule/layout';
	import { CALL_OUTCOME_LABELS, calendarItemTitle, type CalendarItem } from '$lib/jafar/calendar';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import checkboxIcon from '@tabler/icons/outline/checkbox.svg?raw';

	// Jafar business management C2: one thing on the Business Management calendar -- a call, a Busy block or a
	// follow-up -- drawn at whatever size the grid gave it, in the shape of the contractor Schedule's cards. Each
	// kind has its own accent, marker and tag, so colour never carries the difference alone. A passed call still
	// waiting for its outcome says so.
	let {
		item,
		density,
		time,
		passed = false,
		onselect
	}: {
		item: CalendarItem;
		density: CardDensity;
		/** "9am – 9:30am", or "9am" where there is little room, or empty for a day-only follow-up. */
		time: string;
		/** The call has ended; without an outcome it asks for one. */
		passed?: boolean;
		onselect: (item: CalendarItem, element: HTMLElement) => void;
	} = $props();

	const title = $derived(calendarItemTitle(item));
	const business = $derived(
		item.kind === 'call'
			? item.entry.business_name
			: item.kind === 'follow_up'
				? item.followUp.business_name
				: null
	);
	const tag = $derived.by(() => {
		if (item.kind === 'busy') return 'Busy';
		if (item.kind === 'follow_up')
			return item.followUp.first_contact ? 'First contact' : 'Follow-up';
		if (item.entry.status !== 'scheduled')
			return CALL_OUTCOME_LABELS[item.entry.status as keyof typeof CALL_OUTCOME_LABELS];
		return passed ? 'Outcome?' : 'Call';
	});
	const needsOutcome = $derived(
		item.kind === 'call' && item.entry.status === 'scheduled' && passed
	);
	const done = $derived(item.kind === 'call' && item.entry.status !== 'scheduled');
	const icon = $derived(
		item.kind === 'call' ? phoneIcon : item.kind === 'busy' ? lockIcon : checkboxIcon
	);
	const summary = $derived(
		[tag, time, title, business && business !== title ? business : null].filter(Boolean).join(', ')
	);
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class="sales-card sales-card--{item.kind} sales-card--{density}"
	class:sales-card--attention={needsOutcome}
	class:sales-card--done={done}
	aria-label={summary}
	title={summary}
	onclick={(event) => onselect(item, event.currentTarget)}
>
	<span class="sales-card__accent" aria-hidden="true"></span>

	{#if density === 'micro'}
		<span class="sales-card__line">
			<span class="sales-card__marker" aria-hidden="true">{@html icon}</span>
			{#if time}<span class="sales-card__time">{time}</span>{/if}
			<span class="sales-card__title">{title}</span>
		</span>
	{:else}
		<span class="sales-card__time">
			<span class="sales-card__marker" aria-hidden="true">{@html icon}</span>
			{time || tag}
		</span>
		<span class="sales-card__title">{title}</span>
		{#if density === 'standard'}
			{#if business && business !== title}
				<span class="sales-card__business">{business}</span>
			{/if}
			<span class="sales-card__foot">
				<span class="sales-card__tag">{tag}</span>
			</span>
		{/if}
	{/if}
</button>

<style lang="scss">
	.sales-card {
		--sales-card-accent: var(--color-informative);
		--sales-card-tint: var(--color-informative--surface);
		--sales-card-ink: var(--color-informative--onSurface);

		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: var(--space-smaller) var(--space-small) var(--space-smaller)
			calc(var(--space-small) + 2px);
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

	.sales-card--follow_up {
		--sales-card-accent: var(--color-task);
		--sales-card-tint: var(--color-task--surface);
		--sales-card-ink: var(--color-task--onSurface);
	}

	// Busy time recedes: a hatched, quiet block that reads as "not free" rather than as work.
	.sales-card--busy {
		--sales-card-accent: var(--color-inactive);
		--sales-card-tint: var(--color-inactive--surface);
		--sales-card-ink: var(--color-inactive--onSurface);

		background-image: repeating-linear-gradient(
			135deg,
			transparent 0 6px,
			var(--color-inactive--surface) 6px 12px
		);
	}

	.sales-card--attention {
		--sales-card-accent: var(--color-warning);
		--sales-card-tint: var(--color-warning--surface);
		--sales-card-ink: var(--color-warning--onSurface);
	}

	.sales-card--done {
		opacity: 0.72;

		.sales-card__title {
			color: var(--color-text--secondary);
		}
	}

	.sales-card__accent {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: var(--space-smaller);
		background-color: var(--sales-card-accent);
	}

	.sales-card__line {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.sales-card__marker {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--sales-card-ink);

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.sales-card__time {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		white-space: nowrap;
	}

	.sales-card__title,
	.sales-card__business {
		overflow: hidden;
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.sales-card__title {
		color: var(--color-heading);
		font-weight: 600;
	}

	.sales-card__business {
		color: var(--color-text--secondary);
	}

	.sales-card__foot {
		display: flex;
		justify-content: flex-end;
		margin-top: auto;
	}

	.sales-card__tag {
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-small);
		background-color: var(--sales-card-tint);
		color: var(--sales-card-ink);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-loose);
		white-space: nowrap;
	}

	.sales-card--micro {
		justify-content: center;
		padding-top: 0;
		padding-bottom: 0;

		.sales-card__time {
			flex-shrink: 0;
		}

		.sales-card__title {
			flex: 1 1 auto;
			min-width: 0;
			color: var(--color-text);
			font-weight: 500;
		}
	}
</style>
