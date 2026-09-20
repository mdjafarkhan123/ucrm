<script lang="ts">
	// The org's remaining Marketing sending allowance, in plain English -- shown on both Delivery (step 4)
	// and Review (step 5). No reputation/warm-up state exists yet: nothing sends via SES until M4, so there
	// is nothing else to report here until then.
	let { allowance }: { allowance: { state: string; value: number | null; is_unlimited: boolean } } =
		$props();
</script>

<p class="allowance-notice">
	{#if allowance.is_unlimited}
		Your plan allows unlimited Marketing email.
	{:else if allowance.state === 'numeric' && allowance.value !== null}
		Your plan allows {allowance.value} Marketing emails per period.
	{:else}
		Marketing sending allowance isn't turned on for your plan yet.
	{/if}
</p>

<style lang="scss">
	.allowance-notice {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}
</style>
