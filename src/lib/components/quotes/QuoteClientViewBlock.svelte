<script lang="ts">
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import type { QuoteVisibility } from '$lib/quotes/api';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';

	// What the client's copy of this quote actually shows. Each switch is independent: a quote can show
	// line totals while hiding what each unit costs, or show one price for the job and no breakdown at all.
	// Hiding a figure changes the client's copy only — nothing here changes the quote's own arithmetic, and
	// the team always sees every number on this page.
	let {
		saved,
		draft,
		editing = false,
		editable = false,
		changed = false,
		onEdit,
		onChange
	}: {
		saved: QuoteVisibility;
		/** What is staged right now, which is the saved set until somebody changes a switch. */
		draft: QuoteVisibility;
		editing?: boolean;
		editable?: boolean;
		/** True when the staged switches differ from what is saved. */
		changed?: boolean;
		onEdit: () => void;
		onChange: (next: QuoteVisibility) => void;
	} = $props();

	const switches = [
		{ key: 'show_quantities', label: 'Quantities' },
		{ key: 'show_unit_prices', label: 'Unit prices' },
		{ key: 'show_line_totals', label: 'Line item totals' },
		{ key: 'show_totals', label: 'Totals' }
	] as const;
</script>

<!-- Jobber keeps this inside the Product / Service editor, not as a separate document section. -->
<div class="quote-client-view">
	<div class="quote-client-view__heading">
		<span class="quote-client-view__label">
			<span class="quote-client-view__icon" aria-hidden="true">{@html eyeIcon}</span>
			Client view
		</span>
		{#if editable}
			<button type="button" class="quote-client-view__change" onclick={onEdit}>
				{editing ? 'Cancel' : 'Change'}
			</button>
		{/if}
	</div>
	{#if editing}
		<p class="quote-client-view__hint">
			Adjust what your client will see on this quote. Your team always sees every figure.
		</p>
		<div class="quote-client-view__switches">
			{#each switches as entry (entry.key)}
				<Checkbox
					id={`quote-visibility-${entry.key}`}
					label={entry.label}
					checked={draft[entry.key]}
					onchange={(on) => onChange({ ...draft, [entry.key]: on })}
				/>
			{/each}
		</div>
	{/if}
</div>

<style lang="scss">
	.quote-client-view {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding-block: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);

		&__heading,
		&__label {
			display: flex;
			align-items: center;
		}

		&__heading {
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__label {
			gap: var(--space-small);
			color: var(--color-heading);
			font-weight: 600;
		}

		&__icon :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
			color: var(--color-icon--secondary);
		}

		&__change {
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}

	.quote-client-view__hint {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}

	.quote-client-view__switches {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base) var(--space-large);
	}
</style>
