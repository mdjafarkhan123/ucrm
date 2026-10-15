<script lang="ts">
	import Banner from '$lib/components/ui/Banner.svelte';
	import Toast from '$lib/components/ui/Toast.svelte';
	import Tooltip from '$lib/components/ui/Tooltip.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	let dismissed = $state(false);
	let actionTaken = $state(false);
</script>

<svelte:head><title>Feedback preview</title></svelte:head>
<div class="feedback-preview">
	<h1>Feedback preview</h1>
	<Banner type="success" title="Visit scheduled"
		>The crew and customer can now see the visit.</Banner
	>
	<Banner type="warning" title="Quote waiting 6 days">
		Henderson Homes hasn’t answered yet.
		{#snippet action()}<Button variant="secondary" size="small">Follow up</Button>{/snippet}
	</Banner>
	<Banner type="error" title="Couldn’t save the visit">Check the date and try again.</Banner>
	<Banner type="notice">Browser alerts are not set up on this server yet.</Banner>
	<Toast
		title="Changes saved"
		variant="success"
		action={{ label: 'Undo', onSelect: () => (actionTaken = true) }}
		onDismiss={() => (dismissed = true)}
	/>
	<Toast
		title="Couldn’t save changes"
		message="Check your connection and try again."
		variant="error"
		action={{ label: 'Retry', onSelect: () => (actionTaken = true) }}
	/>
	<Toast title="Saving changes…" loading dismissible={false} />
	<Tooltip text="Estimated profit" description="After labour, expenses and tax">
		{#snippet children({ props })}<button {...props} type="button">Estimated profit</button
			>{/snippet}
	</Tooltip>
	<p role="status">
		Dismissed: {dismissed ? 'yes' : 'no'} · Action taken: {actionTaken ? 'yes' : 'no'}
	</p>
</div>

<style lang="scss">
	.feedback-preview {
		display: grid;
		gap: 16px;
		max-width: 700px;
		margin: 24px;
	}
</style>
