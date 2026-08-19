<script lang="ts">
	import type { Freshness } from '$lib/pipeline/freshness';

	// How long the card has been where it is. The colour is a second signal, never the only one: the
	// full sentence goes to screen readers and the short label is on screen for everyone.
	let {
		label,
		freshness,
		description
	}: { label: string; freshness: Freshness; description: string } = $props();
</script>

<span class={`stage-age stage-age--${freshness}`}>
	<span aria-hidden="true">{label}</span>
	<span class="stage-age__spoken">{description}</span>
</span>

<style lang="scss">
	.stage-age {
		display: inline-flex;
		align-items: center;
		width: fit-content;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--stage-age-text);
		background: var(--stage-age-background);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.stage-age--fresh {
		--stage-age-background: var(--color-success--surface);
		--stage-age-text: var(--color-success--onSurface);
	}
	.stage-age--steady {
		--stage-age-background: var(--color-inactive--surface);
		--stage-age-text: var(--color-inactive--onSurface);
	}
	.stage-age--stale {
		--stage-age-background: var(--color-critical--surface);
		--stage-age-text: var(--color-critical--onSurface);
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
