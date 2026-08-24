<script lang="ts">
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// What the quote comes to, read only. Every figure here is one the database worked out and sent back —
	// this card formats money, it never adds it up. Discount and Tax only appear once they are worth
	// something, so a quote with neither reads as Subtotal and Total, not as rows of zeros.
	//
	// Cost, estimated profit and margin are the business's own numbers. They arrive only for someone with
	// `quotes.view_cost`, and a card that was never given them cannot show them.
	let {
		subtotalMinor,
		discountMinor = 0,
		taxMinor = 0,
		totalMinor = null,
		discountLabel = null,
		taxLabel = null,
		costMinor = null,
		profitMinor = null,
		marginBasisPoints = null,
		currencyCode = 'USD',
		locale = 'en-US',
		title = 'Overview'
	}: {
		/** Null when this person may not see quote prices at all. */
		subtotalMinor: number | null;
		discountMinor?: number;
		taxMinor?: number;
		/** Falls back to the subtotal, which is what a quote with no discount or tax comes to. */
		totalMinor?: number | null;
		/** The customer-facing name of the discount, shown beside the amount taken off. */
		discountLabel?: string | null;
		taxLabel?: string | null;
		costMinor?: number | null;
		profitMinor?: number | null;
		marginBasisPoints?: number | null;
		currencyCode?: string;
		locale?: string;
		title?: string;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const total = $derived(totalMinor ?? subtotalMinor ?? 0);
	const showInternal = $derived(costMinor !== null || profitMinor !== null);
	const marginText = $derived(
		marginBasisPoints === null ? '—' : `${(marginBasisPoints / 100).toFixed(1)}%`
	);
</script>

<RailCard {title} icon={receiptIcon}>
	{#if subtotalMinor === null}
		<p class="quote-summary__hidden">You do not have access to quote prices.</p>
	{:else}
		<dl class="quote-summary">
			<div class="quote-summary__row">
				<dt>Subtotal</dt>
				<dd>{money.format(subtotalMinor / 100)}</dd>
			</div>

			{#if discountMinor > 0}
				<div class="quote-summary__row">
					<dt>{discountLabel || 'Discount'}</dt>
					<dd>−{money.format(discountMinor / 100)}</dd>
				</div>
			{/if}

			{#if taxMinor > 0}
				<div class="quote-summary__row">
					<dt>{taxLabel || 'Tax'}</dt>
					<dd>{money.format(taxMinor / 100)}</dd>
				</div>
			{/if}

			<div class="quote-summary__row quote-summary__row--total">
				<dt>Total</dt>
				<dd>{money.format(total / 100)}</dd>
			</div>

			{#if showInternal}
				<div class="quote-summary__internal">
					<p class="quote-summary__internal-title">Only your team sees this</p>
					{#if costMinor !== null}
						<div class="quote-summary__row">
							<dt>Cost</dt>
							<dd>{money.format(costMinor / 100)}</dd>
						</div>
					{/if}
					{#if profitMinor !== null}
						<div class="quote-summary__row">
							<dt>Estimated profit</dt>
							<dd>{money.format(profitMinor / 100)}</dd>
						</div>
					{/if}
					<div class="quote-summary__row">
						<dt>Margin</dt>
						<dd>{marginText}</dd>
					</div>
				</div>
			{/if}
		</dl>
	{/if}
</RailCard>

<style lang="scss">
	.quote-summary {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;

		&__row {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-base);

			dt {
				color: var(--color-text--secondary);
			}
			dd {
				margin: 0;
				color: var(--color-heading);
				font-weight: 600;
			}
		}

		/* The line people actually read. It sits under a rule, the way it does on a printed quote. */
		&__row--total {
			padding-top: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);

			dt {
				color: var(--color-heading);
				font-weight: 700;
			}
			dd {
				font-weight: 700;
			}
		}

		/* The business's own numbers, kept visibly apart from what the customer is quoted. */
		&__internal {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) dashed var(--color-border);
		}

		&__internal-title {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}
	}

	.quote-summary__hidden {
		margin: 0;
		color: var(--color-text--secondary);
	}
</style>
