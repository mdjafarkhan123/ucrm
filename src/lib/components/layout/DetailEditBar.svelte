<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import StickyActionBar from './StickyActionBar.svelte';

	// The save bar every detail page uses. A detail page is read-first: this stays out of the way until a
	// block has been edited, then appears at the bottom to save or throw away everything staged so far.
	// Blocks that save the moment they are clicked — tags, notes, attachments — stay outside the draft, so
	// this bar never claims to be saving them.
	let {
		dirty,
		saving = false,
		error = '',
		message = 'You have changes waiting to be saved.',
		saveLabel = 'Save changes',
		onSave,
		onCancel
	}: {
		/** True once a block has staged a change. The bar renders nothing until then. */
		dirty: boolean;
		saving?: boolean;
		/** Shown in place of the message when a save fails. */
		error?: string;
		message?: string;
		saveLabel?: string;
		onSave: () => void;
		onCancel: () => void;
	} = $props();
</script>

{#if dirty}
	<StickyActionBar>
		<p class="detail-edit-bar__text" role="status">
			{#if error}
				<span class="detail-edit-bar__error">{error}</span>
			{:else}
				{message}
			{/if}
		</p>
		<div class="detail-edit-bar__buttons">
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" onclick={onSave} loading={saving}>{saveLabel}</Button>
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
