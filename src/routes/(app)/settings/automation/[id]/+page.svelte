<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecipeDetailView from '$lib/components/settings/automation/RecipeDetailView.svelte';

	// The read-first home for one automation: header, Overview/History/Versions tabs, and the lifecycle
	// actions (turn on, pause, resume, archive, restore, duplicate). The view owns its own access shell and
	// data, so this page only frames it (docs/automation-behavior-contract.md § Recipe detail).
	const recipeId = $derived(page.params.id ?? '');
</script>

<svelte:head><title>Automation · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[
			{ label: 'Settings', href: resolve('/(app)/settings') },
			{ label: 'Automation', href: resolve('/(app)/settings/automation') },
			{ label: 'Details' }
		]}
	/>

	{#key recipeId}
		<RecipeDetailView {recipeId} />
	{/key}
</PageContainer>
