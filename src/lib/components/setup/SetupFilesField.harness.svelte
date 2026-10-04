<script lang="ts">
	import SetupFilesField from '$lib/components/setup/SetupFilesField.svelte';
	import { PROTECTED_FILE_KINDS } from '$lib/setup/files';

	// For SetupFilesField.svelte.spec.ts only: a protected document question holding the answer the way the
	// setup page does, and showing it, so a test can read what the page would save.
	let { value: initial = '' }: { value?: string } = $props();

	// svelte-ignore state_referenced_locally
	let value = $state(initial);
</script>

<SetupFilesField
	id="setup-test-bill"
	factKey="calls.port_bill"
	label="A recent phone bill"
	kinds={PROTECTED_FILE_KINDS}
	maxFiles={1}
	userId="user-1"
	bind:value
	secure
	oncommit={() => {}}
/>
<output data-testid="value">{value}</output>
