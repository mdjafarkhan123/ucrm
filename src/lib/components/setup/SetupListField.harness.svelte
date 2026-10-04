<script lang="ts">
	import SetupListField from '$lib/components/setup/SetupListField.svelte';
	import type { SetupListField as Field } from '$lib/setup/lists';

	// For SetupListField.svelte.spec.ts only: holds the answer the way the setup page does and shows it, so a
	// test can read what the page would save.
	let {
		fields,
		maxRows,
		value: initial = ''
	}: { fields: Field[]; maxRows: number; value?: string } = $props();

	// svelte-ignore state_referenced_locally
	let value = $state(initial);
	let commits = $state(0);
</script>

<SetupListField
	id="setup-test-list"
	factKey="extra.services"
	label="Your services"
	{fields}
	{maxRows}
	bind:value
	onedit={() => {}}
	oncommit={() => (commits += 1)}
/>
<output data-testid="value">{value}</output>
<output data-testid="commits">{commits}</output>
