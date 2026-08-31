<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import AutomationManageGate from '$lib/components/settings/automation/AutomationManageGate.svelte';
	import PresetLibrary from '$lib/components/settings/automation/PresetLibrary.svelte';
	import RecipeBuilder from '$lib/components/settings/automation/RecipeBuilder.svelte';
	import { emptyAuthoredDefinition } from '$lib/automation/authoring';
	import { getAutomationPreset } from '$lib/automation/presets';

	// /settings/automation/new is the library by default and the builder when a build mode is chosen in the
	// URL (?preset=<key> for a preset starting point, ?mode=scratch for an empty one). Both open a LOCAL draft
	// — no server record exists until the first Save draft in the builder. An unknown preset key falls back to
	// the library rather than a broken form.
	const mode = $derived(page.url.searchParams.get('mode'));
	const presetKey = $derived(page.url.searchParams.get('preset'));
	const preset = $derived(presetKey ? getAutomationPreset(presetKey) : undefined);
	const view = $derived(preset ? 'preset' : mode === 'scratch' ? 'scratch' : 'library');
</script>

<svelte:head><title>New automation · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[
			{ label: 'Settings', href: resolve('/(app)/settings') },
			{ label: 'Automation', href: resolve('/(app)/settings/automation') },
			{ label: view === 'library' ? 'New' : 'Builder' }
		]}
	/>

	<AutomationManageGate>
		{#if view === 'preset' && preset}
			<RecipeBuilder
				mode="create"
				source="preset"
				initialName={preset.name}
				initialDefinition={preset.blueprint}
				presetKey={preset.key}
				presetVersion={preset.version}
			/>
		{:else if view === 'scratch'}
			<RecipeBuilder
				mode="create"
				source="custom"
				initialName=""
				initialDefinition={emptyAuthoredDefinition()}
			/>
		{:else}
			<PageHeader
				eyebrow="Automations"
				title="New automation"
				description="Start from a ready-made automation or build your own from scratch."
			/>
			<PresetLibrary />
		{/if}
	</AutomationManageGate>
</PageContainer>
