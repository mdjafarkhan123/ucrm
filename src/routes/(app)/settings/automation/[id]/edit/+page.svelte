<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import AutomationManageGate from '$lib/components/settings/automation/AutomationManageGate.svelte';
	import RecipeEditorLoader from '$lib/components/settings/automation/RecipeEditorLoader.svelte';

	// /settings/automation/[id]/edit reuses the same builder as /new, loading the recipe's draft first. The
	// manage gate wraps the loader so its editor read only fires for a viewer allowed to edit.
	const recipeId = $derived(page.params.id ?? '');
</script>

<svelte:head><title>Edit automation · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[
			{ label: 'Settings', href: resolve('/(app)/settings') },
			{ label: 'Automation', href: resolve('/(app)/settings/automation') },
			{ label: 'Edit' }
		]}
	/>

	<AutomationManageGate>
		<RecipeEditorLoader {recipeId} />
	</AutomationManageGate>
</PageContainer>
