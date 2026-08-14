<script lang="ts">
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
</script>

<main class="owner-route-skeleton" aria-busy="true" aria-label="Loading page">
	<header class="owner-route-skeleton__header">
		<div class="owner-route-skeleton__heading">
			<LoadingSkeleton variant="heading" label="Loading page title" />
			<LoadingSkeleton variant="text" label="Loading page summary" />
		</div>
		<LoadingSkeleton variant="button" label="Loading page action" />
	</header>

	<section class="owner-route-skeleton__stats" aria-label="Loading summary">
		{#each Array(4) as _, index (index)}
			<LoadingSkeleton variant="card" label="Loading summary card" />
		{/each}
	</section>

	<section class="owner-route-skeleton__panels" aria-label="Loading page content">
		<LoadingSkeleton variant="card" label="Loading primary content" />
		<LoadingSkeleton variant="card" label="Loading secondary content" />
	</section>
</main>

<style lang="scss">
	.owner-route-skeleton {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}

	.owner-route-skeleton__header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.owner-route-skeleton__heading {
		display: grid;
		gap: var(--space-small);
		flex: 1;
		min-width: 0;
	}

	.owner-route-skeleton__stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.owner-route-skeleton__panels {
		display: grid;
		grid-template-columns: minmax(0, 1.35fr) minmax(380px, 1fr);
		gap: var(--space-base);
	}

	@media (max-width: 1100px) {
		.owner-route-skeleton__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}

		.owner-route-skeleton__panels {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 639px) {
		.owner-route-skeleton__header {
			align-items: stretch;
			flex-direction: column;
		}

		.owner-route-skeleton__stats {
			grid-template-columns: 1fr;
		}
	}
</style>
