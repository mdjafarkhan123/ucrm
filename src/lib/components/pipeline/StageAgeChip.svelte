<script lang="ts">
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';

	// How long the card has been where it is: a line of text, never a pill (design `chips.md`, Days-in-stage
	// line). Plain context only — age alone never takes a status colour; the inactivity warning does that. The
	// full sentence goes to screen readers, the short label is on screen. A table whose column already says
	// "In stage" leaves the words off.
	let {
		label,
		description,
		words = true
	}: { label: string; description: string; words?: boolean } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span class="stage-age">
	<span class="stage-age__icon" aria-hidden="true">{@html clockIcon}</span>
	<span class="stage-age__label" aria-hidden="true">{label}</span>
	{#if words}<span class="stage-age__words" aria-hidden="true">in stage</span>{/if}
	<span class="stage-age__spoken">{description}</span>
</span>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.stage-age {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		width: fit-content;
		font-size: var(--typography--fontSize-smaller);
		line-height: 1;
		white-space: nowrap;
	}
	.stage-age__icon {
		display: grid;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	.stage-age__label {
		color: var(--color-heading);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.stage-age__words {
		color: var(--color-text--secondary);
		font-weight: 400;
	}
	.stage-age__spoken {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
</style>
