<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import RecipeBuilder from './RecipeBuilder.svelte';
	import { automationEditorKey, fetchRecipeEditor } from '$lib/settings/automation-authoring';

	// Loads one recipe's editable draft and hands it to the builder. It lives below the manage gate, so its
	// bounded single-row read only fires for a viewer allowed to edit. Mounted fresh per recipe id, it is also
	// what a post-create navigation lands on, so the newly saved draft is read back from the server as the one
	// source of truth rather than carried across in memory.
	let { recipeId }: { recipeId: string } = $props();

	const query = createQuery(() => ({
		queryKey: automationEditorKey(recipeId),
		queryFn: () => fetchRecipeEditor(recipeId)
	}));
</script>

{#if query.isPending}
	<LoadingSkeleton variant="card" rows={3} />
{:else if query.isError}
	<ErrorState
		description="This automation could not be loaded. It may have been removed, or you may not have access."
		retry={() => query.refetch()}
	/>
{:else}
	<RecipeBuilder
		mode="edit"
		source={query.data.source}
		recipeId={query.data.id}
		initialName={query.data.name}
		initialDefinition={query.data.draft_definition}
		initialRevision={query.data.draft_revision}
		presetKey={query.data.preset_key}
		presetVersion={query.data.preset_version}
	/>
{/if}
