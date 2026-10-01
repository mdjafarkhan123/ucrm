<script lang="ts">
	import PackageOfferPage from '$lib/components/packages/PackageOfferPage.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
</script>

<svelte:head>
	<title
		>{data.pkg
			? `${data.pkg.name} · UpliftContractor`
			: 'Package not available · UpliftContractor'}</title
	>
	{#if data.pkg?.promise}<meta name="description" content={data.pkg.promise} />{/if}
</svelte:head>

<main>
	<PackageOfferPage pkg={data.pkg} billing={data.billing} />
</main>
