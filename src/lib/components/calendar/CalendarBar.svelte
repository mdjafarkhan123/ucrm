<script lang="ts" generics="V extends string">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// The shared calendar top bar: step back and forward, Today, the window in words, and the view switch. Used by
	// the contractor Schedule and the Jafar sales calendar; each adds its own buttons through `extras`.

	let {
		view,
		views,
		rangeLabel,
		onstep,
		ontoday,
		onview,
		extras
	}: {
		view: V;
		views: { value: V; label: string; icon?: string; iconColor?: string }[];
		/** The window in words, e.g. "Aug 30 – Sep 5, 2026". The page owns the wording. */
		rangeLabel: string;
		/** Move one whole window back or forward. */
		onstep: (direction: -1 | 1) => void;
		ontoday: () => void;
		onview: (view: V) => void;
		/** Buttons after the view switch. */
		extras?: Snippet;
	} = $props();
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="calendar-bar">
	<div class="calendar-bar__date">
		<div class="calendar-bar__stepper">
			<Button variant="secondary" white iconOnly label={`Previous ${view}`} onclick={() => onstep(-1)}
				>{@html chevronLeftIcon}</Button
			>
			<Button variant="secondary" white onclick={ontoday}>Today</Button>
			<Button variant="secondary" white iconOnly label={`Next ${view}`} onclick={() => onstep(1)}
				>{@html chevronRightIcon}</Button
			>
		</div>

		<p class="calendar-bar__range" aria-live="polite">{rangeLabel}</p>
	</div>

	<div class="calendar-bar__tools">
		<SegmentedControl
			value={view}
			options={views}
			size="small"
			white
			ariaLabel="Calendar view"
			onchange={(next) => onview(next as V)}
		/>
		{@render extras?.()}
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.calendar-bar {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.calendar-bar__date {
		display: flex;
		flex-wrap: wrap;
		min-width: 0;
		align-items: center;
		gap: 10px;
	}

	.calendar-bar__stepper {
		display: inline-flex;
		:global(.button) {
			border-radius: 0;
		}
		:global(.button:first-child) {
			border-radius: var(--radius-base) 0 0 var(--radius-base);
		}
		:global(.button:last-child) {
			border-radius: 0 var(--radius-base) var(--radius-base) 0;
		}
		:global(.button + .button) {
			margin-left: -1px;
		}
		:global(.button:focus-visible) {
			z-index: 1;
		}
	}

	.calendar-bar__range {
		padding-left: 6px;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 700;
		letter-spacing: -0.3px;
		line-height: 1.25;
	}

	.calendar-bar__tools {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
</style>
