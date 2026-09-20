<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';

	// Step 5 (Review) is not built yet (see Memory/campaigns/marketing-growth/NOW.md). The draft up through
	// Delivery is real and already savable, so this is a placeholder, not a dead end.
	let { onBack }: { onBack: () => void } = $props();
</script>

<section class="panel">
	<EmptyState
		icon={clockIcon}
		title="Review is coming soon"
		description="A final read-through summary before you send is the next part of this feature. Everything up to Delivery is saved as a draft whenever you use Save draft above."
	/>
	<div class="panel__foot">
		<Button variant="secondary" variation="subtle" onclick={onBack}>
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
	</div>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		padding: var(--space-large);
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__foot {
			display: flex;
			justify-content: flex-start;
		}
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}
</style>
