<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import LeadForm from '$lib/components/jafar/leads/LeadForm.svelte';

	// Remounts the form for "Save & add another" so every field and warning starts clean.
	let formKey = $state(0);

	function handleSaved(_lead: { id: string; business_name: string }, andAnother: boolean) {
		if (andAnother) {
			formKey += 1;
			return;
		}
		void goto(resolve('/jafar/leads'));
	}
</script>

<svelte:head><title>New Lead · Control Room</title></svelte:head>

{#key formKey}
	<LeadForm onSaved={handleSaved} onCancel={() => goto(resolve('/jafar/leads'))} />
{/key}
