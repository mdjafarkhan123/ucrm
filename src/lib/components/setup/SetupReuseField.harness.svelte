<script lang="ts">
	import SetupField from '$lib/components/setup/SetupField.svelte';
	import type { SetupFact } from '$lib/setup/catalogue';

	// For SetupReuseField.svelte.spec.ts only: a reuse question held the way the setup page holds it, so a test
	// can read what the page would save.
	let { reuse }: { reuse: { lines: string[]; where: string; href: string } | null } = $props();

	const fact: SetupFact = {
		key: 'website.phone',
		label: 'Which phone should the website show?',
		kind: 'phone',
		required: true,
		builtIn: false,
		reuseFrom: 'business.public_phone',
		reuseLabel: 'Public phone',
		reuseSection: { key: 'business', title: 'Your business' }
	};

	let value = $state('');
	let availability = $state<'have' | 'not_yet' | 'need_help'>('have');
	let note = $state('');
</script>

<SetupField
	{fact}
	bind:value
	bind:availability
	bind:note
	{reuse}
	onedit={() => {}}
	oncommit={() => {}}
/>
<output data-testid="value">{value}</output>
