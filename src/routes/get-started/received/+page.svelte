<script lang="ts">
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
</script>

<svelte:head><title>Application received · UpliftContractor</title></svelte:head>

<main class="received">
	<section class="received__card" aria-labelledby="received-title">
		<div class="received__mark" aria-hidden="true">✓</div>
		<div class="received__eyebrow">Application received</div>
		<h1 id="received-title">Thanks, we've got your application</h1>
		{#if data.renderedBody}
			<!-- eslint-disable-next-line svelte/no-at-html-tags -- Jafar-authored template body, same trusted-content pattern as the message-templates preview -->
			<div class="received__body">{@html data.renderedBody}</div>
		{:else}
			<p>
				We'll review your details and follow up by email with next steps, including how to
				complete payment. There's nothing else to do right now.
			</p>
		{/if}
	</section>
</main>

<style lang="scss">
	.received {
		display: flex;
		min-height: 100vh;
		align-items: center;
		justify-content: center;
		padding: var(--space-large);
		background: var(--color-background);
	}
	.received__card {
		max-width: 560px;
		padding: var(--space-extravagant);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		text-align: center;
	}
	.received__mark {
		display: grid;
		width: 56px;
		height: 56px;
		margin: 0 auto var(--space-base);
		place-items: center;
		border-radius: var(--radius-circle);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: 28px;
	}
	.received__eyebrow {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.received__card h1 {
		margin: var(--space-small) 0 var(--space-base);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-jumbo);
	}
	.received__card p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.received__body {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
		text-align: left;
	}
	@media (max-width: 560px) {
		.received__card {
			padding: var(--space-largest) var(--space-large);
		}
	}
</style>
