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
		views: { value: V; label: string }[];
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
			<button
				type="button"
				class="calendar-bar__step"
				aria-label="Previous {view}"
				onclick={() => onstep(-1)}
			>
				{@html chevronLeftIcon}
			</button>
			<button
				type="button"
				class="calendar-bar__step"
				aria-label="Next {view}"
				onclick={() => onstep(1)}
			>
				{@html chevronRightIcon}
			</button>
		</div>

		<Button variant="secondary" size="small" onclick={ontoday}>Today</Button>

		<p class="calendar-bar__range" aria-live="polite">{rangeLabel}</p>
	</div>

	<div class="calendar-bar__tools">
		<SegmentedControl
			value={view}
			options={views}
			size="small"
			onchange={(next) => onview(next as V)}
		/>
		{@render extras?.()}
	</div>
</div>

<style lang="scss">
	.calendar-bar {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.calendar-bar__date {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.calendar-bar__stepper {
		display: flex;
		gap: var(--space-smaller);
	}

	.calendar-bar__step {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 32px;
		height: 32px;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		color: var(--color-icon);
		cursor: pointer;
		transition: background-color var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.calendar-bar__range {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		line-height: var(--typography--lineHeight-large);
	}

	.calendar-bar__tools {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-slim);
	}
</style>
