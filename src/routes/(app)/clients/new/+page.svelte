<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import ClientForm from '$lib/components/clients/ClientForm.svelte';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';

	let savedMessage = $state('');
	// Remounts the form for "Save & create another" so every field, tag, and warning starts clean.
	let formKey = $state(0);

	function handleSaved(client: { id: string; display_name: string }, andAnother: boolean) {
		if (andAnother) {
			savedMessage = `${client.display_name} was saved. Here is a fresh form.`;
			formKey += 1;
			return;
		}
		// The path is resolved; the rule just cannot see through the appended query string that carries
		// the confirmation across to the client's page.
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		void goto(`${resolve('/(app)/clients/[id]', { id: client.id })}?saved=1`);
	}
</script>

<svelte:head><title>New client · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="fill">
	{#if savedMessage}
		<p class="client-new__saved" role="status">
			<span aria-hidden="true">{@html checkIcon}</span>{savedMessage}
		</p>
	{/if}

	{#key formKey}
		<ClientForm onSaved={handleSaved} onCancel={() => goto(resolve('/clients'))} />
	{/key}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-new__saved {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-small);

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}
</style>
