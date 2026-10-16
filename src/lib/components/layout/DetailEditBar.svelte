<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import StickyActionBar from './StickyActionBar.svelte';

	// The save bar every detail page uses. A detail page is read-first: this stays out of the way until a
	// block is opened for editing, then appears at the bottom to save or throw away everything staged so
	// far. Blocks that save the moment they are clicked — tags, notes, attachments — stay outside the
	// draft, so this bar never claims to be saving them.
	//
	// Opening a block and changing something are two different things, and the bar owns what each one
	// means so every detail page behaves the same way. Opening one shows the bar, because Cancel is the
	// only way back out of an editor. Save stays greyed out until something has actually changed, so it
	// never offers to write a change nobody made.
	let {
		editing = false,
		dirty,
		saving = false,
		error = '',
		message = 'You have changes waiting to be saved.',
		editingMessage = 'Make your changes, then save them here.',
		saveLabel = 'Save changes',
		onSave,
		onCancel
	}: {
		/** True while any block is open for editing, changed or not. Shows the bar so Cancel is reachable. */
		editing?: boolean;
		/** True once a block has staged a real change. Shows the bar, and enables Save. */
		dirty: boolean;
		saving?: boolean;
		/** Shown in place of the message when a save fails. */
		error?: string;
		message?: string;
		/** Shown while a block is open but nothing has changed yet. */
		editingMessage?: string;
		saveLabel?: string;
		onSave: () => void;
		onCancel: () => void;
	} = $props();
</script>

{#if editing || dirty}
	<StickyActionBar>
		<p class="detail-edit-bar__text" role="status">
			{#if error}
				<span class="detail-edit-bar__error">{error}</span>
			{:else if dirty}
				{message}
			{:else}
				{editingMessage}
			{/if}
		</p>
		<div class="detail-edit-bar__buttons">
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" onclick={onSave} loading={saving} disabled={!dirty}>
				{saveLabel}
			</Button>
		</div>
	</StickyActionBar>
{/if}

<style lang="scss">
	.detail-edit-bar {
		&__text {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}

		&__buttons {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-small);
		}
	}
</style>
