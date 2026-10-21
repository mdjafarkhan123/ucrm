<script lang="ts">
	import type { Snippet } from 'svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Input from '$lib/components/ui/Input.svelte';

	// The shared create form (design skill `layout.md` → Create pages, Pencil `OjBZG`): the first card on
	// New request, quote, job and invoice. A top in the record's own colour holds the page title and the
	// Title field; under it the client picker fills the left and the record's own fact sits at the right,
	// read-only. Only the colour, the words and that fact change between the four.
	let {
		title = $bindable(''),
		id = 'create-form',
		tone,
		icon,
		heading,
		description,
		titleId,
		titleLabel = 'Title',
		titlePlaceholder = '',
		titleRequired = false,
		titleInvalid = false,
		titleError = '',
		factIcon,
		factTone,
		factLabel,
		factValue,
		client,
		class: className = ''
	}: {
		title?: string;
		/** Prefix for the ids inside the card, so two of these can never collide. */
		id?: string;
		/** The record's colour family: `request`, `quote`, `job` or `invoice`. */
		tone: string;
		/** Tabler icon for this kind of record, imported with `?raw`. */
		icon: string;
		/** The page title, e.g. "New job". */
		heading: string;
		description: string;
		/** Id for the page title, so the page frame can name its form after it. */
		titleId?: string;
		/** The title field's label; Invoice says "Subject". */
		titleLabel?: string;
		titlePlaceholder?: string;
		titleRequired?: boolean;
		titleInvalid?: boolean;
		titleError?: string;
		/** The record's own fact at the right: a number given on save, or the day it was asked for. */
		factIcon: string;
		/** The fact tile's colour; the record's own unless given. */
		factTone?: string;
		factLabel: string;
		factValue: string;
		/** The client picker, with any property controls under it. */
		client: Snippet;
		class?: string;
	} = $props();
</script>

<section class={`create-form ${className}`}>
	<div
		class="create-form__top tinted-surface"
		style:background={`var(--color-${tone}--surface)`}
		style:border-color={`var(--color-${tone}--surface-edge)`}
	>
		<div class="create-form__heading">
			<IconTile {icon} {tone} size={40} white />
			<div class="create-form__words">
				<h1 id={titleId} class="create-form__title">{heading}</h1>
				<p class="create-form__description" style:color={`var(--color-${tone}--onSurface)`}>
					{description}
				</p>
			</div>
		</div>
		<Input
			id={`${id}-title`}
			label={titleLabel}
			placeholder={titlePlaceholder}
			bind:value={title}
			required={titleRequired}
			invalid={titleInvalid}
			errorMessage={titleError}
		/>
	</div>

	<div class="create-form__body">
		<div class="create-form__client">{@render client()}</div>
		<div class="create-form__fact">
			<IconTile icon={factIcon} tone={factTone ?? tone} size={32} />
			<div class="create-form__fact-words">
				<span class="create-form__fact-label">{factLabel}</span>
				<span class="create-form__fact-value">{factValue}</span>
			</div>
		</div>
	</div>
</section>

<style lang="scss">
	.create-form {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__top {
			display: flex;
			flex-direction: column;
			gap: 18px;
			padding: var(--space-medium) var(--space-large) 22px;
			border-bottom: var(--border-base) solid;
		}

		&__heading {
			display: flex;
			align-items: center;
			gap: 14px;
		}

		&__words {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 2px;
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			letter-spacing: -0.5px;
			line-height: var(--typography--lineHeight-tight);
		}

		&__description {
			margin: 0;
			font-size: var(--typography--fontSize-base);
		}

		&__body {
			display: flex;
			align-items: flex-end;
			gap: var(--space-large);
			padding: var(--space-medium) var(--space-large) var(--space-large);
		}

		&__client {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 6px;
		}

		// Read-only, never a field box: the record's fact on a quiet tile.
		&__fact {
			display: flex;
			flex: 0 0 208px;
			align-items: center;
			gap: 10px;
			height: 63px;
			padding: 0 var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__fact-words {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__fact-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__fact-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			white-space: nowrap;
		}
	}

	@media (max-width: 767px) {
		.create-form__body {
			flex-direction: column;
			align-items: stretch;
		}
		.create-form__fact {
			flex-basis: auto;
		}
	}
</style>
