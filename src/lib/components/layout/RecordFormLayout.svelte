<script lang="ts">
	import type { Snippet } from 'svelte';
	import StickyActionBar from './StickyActionBar.svelte';
	import PageHeader from './PageHeader.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';

	// The shape every create and edit page shares: a titled main card, a right rail of cards, and the
	// action bar underneath. Each page decides what goes in the rail, so a request page can show Notes and
	// Attachments while a client page also shows Lead source.
	//
	// It also owns the form-level error banner. A page passes its `error` text here instead of drawing its
	// own banner, and calls `revealError()` after a failed save so the message scrolls into view and takes
	// focus — the person is almost always down by the Save button when a save fails, and an off-screen
	// banner is why Save "looks broken".
	let {
		title,
		icon,
		main,
		rail,
		actions,
		error = '',
		errorFields = [],
		concept = false,
		description,
		tone = 'inactive',
		headerAside,
		status,
		pageHeader = true,
		labelledBy,
		class: className = ''
	}: {
		title: string;
		icon?: string;
		main: Snippet;
		rail?: Snippet;
		actions?: Snippet;
		error?: string;
		errorFields?: { anchor: string; label: string }[];
		/** The concept look (New job `zUFDO`): a page header with its tile, title and description, the
		 *  main column's blocks as separate cards on the page, and a floating save bar that says where the
		 *  form stands. */
		concept?: boolean;
		/** Concept only: the line under the title. */
		description?: string;
		/** Concept only: the title tile's colour family, the record's (`job`, `quote`…). */
		tone?: string;
		/** Concept only: what sits at the right of the page header, e.g. the "Job #" pill. */
		headerAside?: Snippet;
		/** Concept only: the save bar's left side, saying where the form stands. */
		status?: Snippet;
		/** Concept only: false when the main column opens with the shared create form, which carries the
		 *  page title itself (`CreateFormHeader`). */
		pageHeader?: boolean;
		/** Concept only, with `pageHeader` off: the id of that page title. */
		labelledBy?: string;
		class?: string;
	} = $props();

	const uid = $props.id();
	const titleId = $derived(labelledBy ?? `${uid}-title`);

	let errorSummary = $state<FormErrorSummary>();

	export function revealError() {
		void errorSummary?.reveal();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if concept}
	<div class={`record-form record-form--concept ${className}`}>
		{#if pageHeader}
			<PageHeader
				{title}
				{description}
				{icon}
				{tone}
				{titleId}
				actions={headerAside}
				class="record-form__page-header"
			/>
		{/if}
		<FormErrorSummary bind:this={errorSummary} message={error} fields={errorFields} />
		<div class={['record-form__grid', !rail && 'record-form__grid--no-rail']}>
			<section class="record-form__main" aria-labelledby={titleId}>{@render main()}</section>
			{#if rail}
				<aside class="record-form__rail">{@render rail()}</aside>
			{/if}
		</div>

		{#if actions}
			<StickyActionBar concept>
				<div class="record-form__status">{@render status?.()}</div>
				<div class="record-form__actions">{@render actions()}</div>
			</StickyActionBar>
		{/if}
	</div>
{:else}
	<div class={`record-form ${className}`}>
		<div class={['record-form__grid', !rail && 'record-form__grid--no-rail']}>
			<section class="record-form__main" aria-labelledby={titleId}>
				<header class="record-form__header">
					{#if icon}<span class="record-form__icon" aria-hidden="true">{@html icon}</span>{/if}
					<h1 id={titleId}>{title}</h1>
				</header>
				<FormErrorSummary bind:this={errorSummary} message={error} fields={errorFields} />
				{@render main()}
			</section>

			{#if rail}
				<aside class="record-form__rail">{@render rail()}</aside>
			{/if}
		</div>

		{#if actions}
			<StickyActionBar>{@render actions()}</StickyActionBar>
		{/if}
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.record-form {
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

		&__header {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			h1 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
				line-height: var(--typography--lineHeight-tight);
			}
		}

		&__icon :global(svg) {
			display: block;
			width: 20px;
			height: 20px;
			color: var(--color-icon--secondary);
		}

		&__rail {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);

			> :global(*) {
				flex-shrink: 0;
			}
		}
	}

	// Concept look: no white sheet. The page header sits above the columns, each block in the main column is
	// its own card 24 apart, and the rail is 360 wide, as drawn in `zUFDO`.
	.record-form--concept {
		gap: var(--space-large);

		:global(.record-form__page-header) {
			margin-bottom: 0;
		}
		:global(.record-form__page-header .page-header__description) {
			max-width: none;
		}

		// The rail's summary stays in view while the form scrolls under it.
		.record-form__rail {
			position: sticky;
			top: 0;
		}

		.record-form__grid {
			grid-template-columns: minmax(0, 1fr) 360px;

			&--no-rail {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		.record-form__main {
			gap: var(--space-large);
			padding: 0;
			border: 0;
			border-radius: 0;
			background: transparent;
			box-shadow: none;

			> :global(*) {
				flex-shrink: 0;
			}
		}
	}

	.record-form__status {
		display: flex;
		flex: 1 1 auto;
		min-width: 0;
		align-items: center;
		gap: var(--space-small);
	}

	.record-form__actions {
		display: flex;
		flex: 0 0 auto;
		gap: var(--space-small);
	}

	/* Two columns side by side: when the page gives this layout the screen's height, the form and the rail
	 * each scroll on their own, as RecordDetailLayout does, so scrolling over the rail never carries the
	 * form away and leaves an empty column. Where the page does not (its wrapper has no set height),
	 * `height: 100%` falls back to auto and the page keeps scrolling as one. No `overscroll-behavior:
	 * contain` here: in that fallback it would stop the wheel from reaching the page at all. */
	@media (min-width: 1080px) {
		.record-form {
			height: 100%;
		}
		.record-form__grid {
			flex: 1 1 auto;
			min-height: 0;
		}
		.record-form__main,
		.record-form__rail {
			max-height: 100%;
			overflow-y: auto;
		}
	}

	@media (max-width: 1079px) {
		.record-form__grid,
		.record-form--concept .record-form__grid {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	@media (max-width: 767px) {
		.record-form__main {
			padding: var(--space-base);
		}
	}
</style>
