<script lang="ts">
	import type { Snippet } from 'svelte';
	import DetailEditBar from './DetailEditBar.svelte';

	// The shape every record's detail page shares: a main column of blocks, a right rail of cards, and the
	// save bar that appears as soon as a block is opened for editing. A detail page is read-first, so
	// nothing here is a form — blocks stage their edits and this bar commits them.
	//
	// A page reports two facts about its own blocks — which are open, and which have really changed — and
	// `DetailEditBar` decides what to do with them, so no page has to work out when the bar shows or when
	// Save is allowed.
	//
	// Its sibling is `RecordFormLayout`, the shell for full-page create forms, whose action bar is always
	// visible because that whole page is one form.
	let {
		header,
		main,
		rail,
		editing = false,
		dirty = false,
		saving = false,
		error = '',
		barMessage,
		editingMessage,
		saveLabel,
		onSave,
		onCancel,
		cards = false,
		concept = false,
		class: className = ''
	}: {
		/** The record's header card, full width above both columns (the concept look). */
		header?: Snippet;
		main: Snippet;
		rail?: Snippet;
		/** True while a block is open for editing, changed or not, so Cancel is always within reach. */
		editing?: boolean;
		/** True once a block has staged a real change. Omit on a page that cannot be edited yet. */
		dirty?: boolean;
		saving?: boolean;
		error?: string;
		barMessage?: string;
		editingMessage?: string;
		saveLabel?: string;
		onSave?: () => void;
		onCancel?: () => void;
		/** The "App look" page: blocks are separate cards sitting straight on the app background, with the
		 *  rail beside them, instead of one white sheet holding bordered blocks. Other record pages keep
		 *  the sheet until they are converted. */
		cards?: boolean;
		/** The concept look (Job details `tNdkX`): a 360px rail and 24px between every card. Needs `cards`. */
		concept?: boolean;
		class?: string;
	} = $props();
</script>

<div
	class={`record-detail ${className} scroll-y-auto`}
	class:record-detail--cards={cards}
	class:record-detail--concept={concept}
>
	{#if header}
		<div class="record-detail__header">{@render header()}</div>
	{/if}
	<div class="record-detail__grid scroll-y-auto" class:record-detail__grid--no-rail={!rail}>
		<div class="record-detail__main scroll-y-auto">{@render main()}</div>
		{#if rail}
			<aside class="record-detail__rail scroll-y-auto">{@render rail()}</aside>
		{/if}
	</div>

	{#if onSave && onCancel}
		<DetailEditBar
			{editing}
			{dirty}
			{saving}
			{error}
			message={barMessage}
			{editingMessage}
			{saveLabel}
			{onSave}
			{onCancel}
		/>
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
			padding: var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);

			// Like the rail, the column scrolls: its blocks keep their full height.
			> :global(*) {
				flex-shrink: 0;
			}
		}

		&__rail {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding-bottom: var(--space-base);

			// The rail scrolls; its cards keep their full height instead of squeezing to fit the window.
			> :global(*) {
				flex-shrink: 0;
			}
		}
	}

	// App look. Each block is its own white card on the grey page; nothing wraps the column. The rail is a
	// fixed 336px beside it, and 20px separates the two columns, as in the approved Job details design.
	.record-detail--cards {
		gap: 0;

		.record-detail__grid {
			grid-template-columns: minmax(0, 1fr) 336px;
			gap: var(--space-large);

			&--no-rail {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		.record-detail__main {
			gap: 20px;
			padding: 0;
			border-radius: 0;
			background: transparent;
			box-shadow: none;
		}

		.record-detail__rail {
			gap: var(--space-base);
			padding-bottom: 0;
		}
	}

	// Concept look: the header card spans both columns, then a 24px gap, then the columns.
	.record-detail--concept {
		gap: var(--space-large);

		.record-detail__grid {
			grid-template-columns: minmax(0, 1fr) 360px;

			&--no-rail {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		.record-detail__main {
			gap: var(--space-large);
		}
	}

	@media (max-width: 1079px) {
		.record-detail__grid,
		.record-detail--cards .record-detail__grid {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 767px) {
		.record-detail__main {
			padding: var(--space-base);
		}
	}
</style>
