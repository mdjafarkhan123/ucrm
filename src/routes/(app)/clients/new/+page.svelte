<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import ClientForm from '$lib/components/clients/ClientForm.svelte';

	// Remounts the form for "Save & create another" so every field, tag, and warning starts clean.
	let formKey = $state(0);

	function handleSaved(client: { id: string; display_name: string }, andAnother: boolean) {
		if (andAnother) {
			formKey += 1;
			return;
		}
		void goto(resolve('/(app)/clients/[id=uuid]', { id: client.id }));
	}
</script>

<svelte:head><title>New client · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	{#key formKey}
		<ClientForm onSaved={handleSaved} onCancel={() => goto(resolve('/clients'))} />
	{/key}
</PageContainer>
