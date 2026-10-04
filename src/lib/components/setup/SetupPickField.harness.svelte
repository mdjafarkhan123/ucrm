<script lang="ts">
	import SetupPickField from '$lib/components/setup/SetupPickField.svelte';
	import type { SetupListRow } from '$lib/setup/lists';

	// For SetupPickField.svelte.spec.ts only: holds the answer the way the setup page does and shows it, so a
	// test can read what the page would save.
	let {
		rows,
		ordered = false,
		maxChoices,
		value: initial = ''
	}: { rows: SetupListRow[]; ordered?: boolean; maxChoices?: number; value?: string } = $props();

	// svelte-ignore state_referenced_locally
	let value = $state(initial);
</script>

<SetupPickField
	id="setup-test-pick"
	label="Which services should we promote first?"
	{rows}
	nameKey="name"
	minChoices={2}
	{maxChoices}
	{ordered}
	bind:value
	oncommit={() => {}}
/>
<output data-testid="value">{value}</output>
