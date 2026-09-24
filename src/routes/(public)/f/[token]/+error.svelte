<script lang="ts">
	// What an unknown, turned-off or expired file share link shows. One page for all three, so a stranger
	// walking the URL space learns nothing about which links once existed.
</script>

<svelte:head>
	<title>Link not available</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<main class="share-unavailable">
	<h1>This link is not available</h1>
	<p>
		The link may be mistyped, or it may no longer be active. Ask the business that sent it for a new
		one.
	</p>
</main>

<style lang="scss">
	.share-unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-largest);
		text-align: center;
		background: var(--color-surface--background);
		color: var(--color-text);

		h1 {
			margin: 0;
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tightest);
			color: var(--color-heading);
		}

		p {
			margin: 0;
			max-width: 44ch;
			color: var(--color-text--secondary);
		}
	}
</style>
