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
			<span class="calendar-bar__split" aria-hidden="true"></span>
			<button
				type="button"
				class="calendar-bar__step"
				aria-label="Next {view}"
				onclick={() => onstep(1)}
			>
				{@html chevronRightIcon}
			</button>
		</div>

		<Button variant="secondary" onclick={ontoday}>Today</Button>

		<p class="calendar-bar__range" aria-live="polite">{rangeLabel}</p>
	</div>

	<div class="calendar-bar__tools">
		<SegmentedControl
			value={view}
			options={views}
			size="small"
			tone="plain"
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
		align-items: center;
		gap: 10px;
	}

	// The two arrows are one joined control, so they read as "move the window" rather than two buttons.
	.calendar-bar__stepper {
		display: flex;
		align-items: center;
		box-sizing: border-box;
		height: 36px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
	}

	.calendar-bar__split {
		width: 1px;
		height: 20px;
		background-color: var(--color-border--interactive);
	}

	.calendar-bar__step {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 36px;
		height: 36px;
		padding: 0;
		border: none;
		border-radius: var(--radius-base);
		background: none;
		color: var(--color-text);
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
			width: 16px;
			height: 16px;
		}
	}

	.calendar-bar__range {
		padding-left: 6px;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		letter-spacing: -0.3px;
		line-height: var(--typography--lineHeight-large);
	}

	.calendar-bar__tools {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
</style>
