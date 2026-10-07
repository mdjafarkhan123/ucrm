<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';

	// Jafar business management B2b: one block of a Lead's page opened for editing in place (Jobber's pattern 1,
	// as on a client's page). Its own Save writes there and then; Save stays off until something changed.
	let {
		label,
		dirty,
		saving = false,
		error = '',
		onSave,
		onCancel,
		children
	}: {
		/** Names the form for a screen reader, e.g. "Edit business details". */
		label: string;
		dirty: boolean;
		saving?: boolean;
		error?: string;
		onSave: () => void;
		onCancel: () => void;
		children: Snippet;
	} = $props();
</script>

<form
	class="lead-block-editor"
	aria-label={label}
	novalidate
	onsubmit={(event) => {
		event.preventDefault();
		if (dirty && !saving) onSave();
	}}
>
	{@render children()}

	{#if error}
		<p class="lead-block-editor__error" role="alert">{error}</p>
	{/if}

	<div class="lead-block-editor__actions">
		<Button variant="tertiary" size="small" onclick={onCancel} disabled={saving}>Cancel</Button>
		<Button variant="primary" size="small" type="submit" loading={saving} disabled={!dirty}>
			Save
		</Button>
	</div>
</form>

<style lang="scss">
	.lead-block-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
