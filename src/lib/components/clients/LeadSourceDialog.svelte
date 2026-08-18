<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';

	// Edits lead source without saving it. Done hands the choice back to the page's draft.
	let {
		open,
		value,
		onDone,
		onClose
	}: {
		open: boolean;
		value: string;
		onDone: (next: string) => void;
		onClose: () => void;
	} = $props();

	const LEAD_SOURCES = [
		'Referral',
		'Google search',
		'Website',
		'Social media',
		'Repeat customer',
		'Drive by',
		'Other'
	];

	// Taken once on mount; the page mounts this fresh each time it opens.
	let choice = $state(untrack(() => value));

	const options = $derived([
		{ value: '', label: 'Not recorded' },
		...LEAD_SOURCES.map((source) => ({ value: source, label: source })),
		// Keeps a source saved before this list existed visible instead of silently blanking it.
		...(choice && !LEAD_SOURCES.includes(choice) ? [{ value: choice, label: choice }] : [])
	]);
</script>

<Dialog {open} title="Lead source" size="small" {onClose}>
	<div class="lead-source-dialog">
		<Select
			id="lead-source-dialog-select"
			value={choice}
			{options}
			onchange={(next) => (choice = next)}
		/>
		<p class="lead-source-dialog__hint">
			Where this client came from, so you know what brings work in.
		</p>

		<div class="lead-source-dialog__actions">
			<Button variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button variant="primary" onclick={() => onDone(choice)}>Done</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.lead-source-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
