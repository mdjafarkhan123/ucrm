<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';

	// Steps 3-5 (email editor, delivery, review) are not built yet -- this session's slice is the
	// Campaigns list plus the Goal and Customers steps (see Memory/campaigns/marketing-growth/NOW.md). The
	// draft up to Customers is real and already savable, so this is a placeholder, not a dead end.
	let { onBack }: { onBack: () => void } = $props();
</script>

<section class="panel">
	<EmptyState
		icon={clockIcon}
		title="The rest of this journey is coming soon"
		description="Building the message, choosing delivery, and reviewing before you send are the next parts of this feature. Your goal and customers are saved as a draft whenever you use Save draft above."
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
