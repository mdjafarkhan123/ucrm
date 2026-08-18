<script lang="ts">
	import type { Snippet } from 'svelte';
	import DetailEditBar from './DetailEditBar.svelte';

	// The shape every record's detail page shares: a main column of blocks, a right rail of cards, and the
	// save bar that appears only once a block has been edited. A detail page is read-first, so nothing here
	// is a form — blocks stage their edits and this bar commits them.
	//
	// Its sibling is `RecordFormLayout`, the shell for full-page create forms, whose action bar is always
	// visible because that whole page is one form.
	let {
		main,
		rail,
		dirty = false,
		saving = false,
		error = '',
		barMessage,
		saveLabel,
		onSave,
		onCancel,
		class: className = ''
	}: {
		main: Snippet;
		rail?: Snippet;
		/** True once a block has staged a change. Omit on a page that cannot be edited yet. */
		dirty?: boolean;
		saving?: boolean;
		error?: string;
		barMessage?: string;
		saveLabel?: string;
		onSave?: () => void;
		onCancel?: () => void;
		class?: string;
	} = $props();
</script>

<div class={`record-detail ${className}`}>
	<div class="record-detail__grid" class:record-detail__grid--no-rail={!rail}>
		<div class="record-detail__main">{@render main()}</div>
		{#if rail}
			<aside class="record-detail__rail">{@render rail()}</aside>
		{/if}
	</div>

	{#if onSave && onCancel}
		<DetailEditBar {dirty} {saving} {error} message={barMessage} {saveLabel} {onSave} {onCancel} />
	{/if}
</div>

<style lang="scss">
	.record-detail {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(300px, 360px);
			align-items: start;
			gap: var(--space-large);

			&--no-rail {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		&__main {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);
		}

		&__rail {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}
	}

	@media (max-width: 1079px) {
		.record-detail__grid {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 767px) {
		.record-detail__main {
			padding: var(--space-base);
		}
	}
</style>
