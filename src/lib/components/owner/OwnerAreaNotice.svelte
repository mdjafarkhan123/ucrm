<script lang="ts">
	let { title, description, icon }: { title: string; description: string; icon: string } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="owner-area-notice" aria-labelledby="owner-area-notice-title">
	<span class="owner-area-notice__icon" aria-hidden="true">{@html icon}</span>
	<h1 id="owner-area-notice-title">{title}</h1>
	<p>{description}</p>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.owner-area-notice {
		display: grid;
		min-height: 360px;
		place-items: center;
		gap: var(--space-base);
		padding: var(--space-largest);
		border: var(--border-base) dashed var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.owner-area-notice__icon {
		display: grid;
		width: 56px;
		height: 56px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.owner-area-notice__icon :global(svg) {
		width: 28px;
		height: 28px;
	}
	h1 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
	}
	p {
		max-width: 50ch;
		line-height: var(--typography--lineHeight-large);
	}
</style>
