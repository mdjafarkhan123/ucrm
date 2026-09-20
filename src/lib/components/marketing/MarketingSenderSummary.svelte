<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';

	// The verified Marketing sender and where replies land -- shown read-only on both Delivery (step 4) and
	// Review (step 5), since neither step lets the contractor change it yet (see delivery-options.ts's
	// comment on why a sender picker is out of scope until M4).
	let { sender }: { sender: { display_name: string; email_address: string } | null } = $props();
</script>

<div class="sender-summary">
	{#if sender}
		<p class="sender-summary__identity">
			<b>{sender.display_name}</b>
			<span>&lt;{sender.email_address}&gt;</span>
		</p>
		<p class="sender-summary__hint">
			Replies land in your shared Conversations inbox, linked back to this campaign.
		</p>
	{:else}
		<p class="sender-summary__warning">
			You don't have a verified sender yet.
			<Button variant="secondary" variation="subtle" size="small" href="/settings/communications">
				Set up a sender
			</Button>
		</p>
	{/if}
</div>

<style lang="scss">
	.sender-summary {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__identity {
			display: flex;
			align-items: baseline;
			gap: var(--space-smaller);
			margin: 0;

			span {
				color: var(--color-text--secondary);
			}
		}

		&__hint {
			margin: 0;
			font-size: var(--typography--fontSize-small);
			color: var(--color-text--secondary);
		}

		&__warning {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-warning--onSurface);
		}
	}
</style>
