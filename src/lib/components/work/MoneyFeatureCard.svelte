<script lang="ts">
	// The dark money card beside a work list's overview: one big figure with a line under it, and a
	// second figure below a hairline. It reads from the reverse tokens, so it is dark in the light theme
	// and light in the dark theme.
	let {
		eyebrow,
		value,
		note,
		detailLabel,
		detailValue,
		loading = false
	}: {
		eyebrow: string;
		value: string;
		note?: string;
		detailLabel?: string;
		detailValue?: string;
		loading?: boolean;
	} = $props();
</script>

<section class="money-card" aria-label={eyebrow} aria-busy={loading}>
	<p class="money-card__eyebrow">{eyebrow}</p>
	<div class="money-card__figure">
		<p class="money-card__value">{value}</p>
		{#if note}<p class="money-card__note">{note}</p>{/if}
	</div>
	{#if detailLabel}
		<dl class="money-card__detail">
			<dt>{detailLabel}</dt>
			<dd>{detailValue ?? '—'}</dd>
		</dl>
	{/if}
</section>

<style lang="scss">
	.money-card {
		display: flex;
		min-width: 0;
		flex-direction: column;
		justify-content: space-between;
		gap: var(--space-large);
		padding: var(--space-large);
		border-radius: var(--radius-base);
		color: var(--color-text--reverse);
		background: var(--color-surface--reverse);

		&__eyebrow {
			color: var(--color-icon--secondary);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 1px;
			text-transform: uppercase;
		}
		&__figure {
			display: grid;
			gap: 6px;
		}
		&__value {
			color: var(--color-text--reverse);
			font-size: 32px;
			font-variant-numeric: tabular-nums;
			font-weight: 700;
			letter-spacing: -1.2px;
			line-height: 1;
			overflow-wrap: anywhere;
		}
		&__note {
			color: var(--color-icon--secondary);
			font-size: 13px;
			font-weight: 500;
		}
		&__detail {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin: 0;
			padding-top: 14px;
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 14%, transparent);
			font-size: 13px;

			dt {
				font-weight: 500;
			}
			dd {
				margin: 0;
				font-variant-numeric: tabular-nums;
				font-weight: 600;
			}
		}
	}
</style>
