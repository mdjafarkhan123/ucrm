<script lang="ts">
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
</script>

<main class="route-skeleton" aria-busy="true" aria-label="Loading page">
	<header class="route-skeleton__header">
		<div class="route-skeleton__heading">
			<LoadingSkeleton variant="heading" label="Loading page title" />
			<LoadingSkeleton variant="text" label="Loading page summary" />
		</div>
		<LoadingSkeleton variant="button" label="Loading page action" />
	</header>

	<section class="route-skeleton__stats" aria-label="Loading summary">
		{#each Array(4) as _, index (index)}
			<LoadingSkeleton variant="card" label="Loading summary card" />
		{/each}
	</section>

	<section class="route-skeleton__panels" aria-label="Loading page content">
		<LoadingSkeleton variant="card" label="Loading primary content" />
		<LoadingSkeleton variant="card" label="Loading secondary content" />
	</section>
</main>

<style lang="scss">
	.route-skeleton {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}

	.route-skeleton__header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.route-skeleton__heading {
		display: grid;
		gap: var(--space-small);
		flex: 1;
		min-width: 0;
	}

	.route-skeleton__stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.route-skeleton__panels {
		display: grid;
		grid-template-columns: minmax(0, 1.35fr) minmax(380px, 1fr);
		gap: var(--space-base);
	}

	@media (max-width: 1100px) {
		.route-skeleton__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}

		.route-skeleton__panels {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 639px) {
		.route-skeleton__header {
			align-items: stretch;
			flex-direction: column;
		}

		.route-skeleton__stats {
			grid-template-columns: 1fr;
		}
	}
</style>
