<script lang="ts">
	// How long the card has been where it is. Plain context only: age alone never colours a card — the
	// inactivity warning does that. The full sentence goes to screen readers, the short label is on screen.
	let { label, description }: { label: string; description: string } = $props();
</script>

<span class="stage-age">
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
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 1;
		font-variant-numeric: tabular-nums;
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
