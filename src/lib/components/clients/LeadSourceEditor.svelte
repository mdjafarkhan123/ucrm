<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { LEAD_SOURCES } from '$lib/clients/lead-sources';

	// Lead source, edited inside its own rail card (Jobber's pattern 1). Save writes there and then.
	let {
		value,
		saving = false,
		error = '',
		onSave,
		onCancel
	}: {
		value: string;
		saving?: boolean;
		error?: string;
		onSave: (next: string) => void;
		onCancel: () => void;
	} = $props();

	// Taken once on mount; the page mounts this fresh each time it opens.
	let choice = $state(untrack(() => value));

	const options = $derived([
		{ value: '', label: 'Not recorded' },
		...LEAD_SOURCES.map((source) => ({ value: source, label: source })),
		// Keeps a source saved before this list existed visible instead of silently blanking it.
		...(choice && !LEAD_SOURCES.includes(choice) ? [{ value: choice, label: choice }] : [])
	]);
</script>

<form
	class="lead-source-editor"
	aria-label="Lead source"
	onsubmit={(event) => {
		event.preventDefault();
		onSave(choice);
	}}
>
	<Select
		id="lead-source-editor-select"
		value={choice}
		{options}
		onchange={(next) => (choice = next)}
	/>
	<p class="lead-source-editor__hint">
		Where this client came from, so you know what brings work in.
	</p>

	{#if error}
		<p class="lead-source-editor__error" role="alert">{error}</p>
	{/if}

	<div class="lead-source-editor__actions">
		<Button variant="tertiary" size="small" onclick={onCancel} disabled={saving}>Cancel</Button>
		<Button variant="primary" size="small" type="submit" loading={saving}>Save</Button>
	</div>
</form>

<style lang="scss">
	.lead-source-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
