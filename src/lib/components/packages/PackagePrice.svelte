<script lang="ts">
	import { formatUsd } from '$lib/jafar/packages';
	import {
		offerHeadline,
		priceParts,
		yearlySaving,
		type BillingInterval,
		type PublicPackage
	} from '$lib/packages/public-package';

	// Package builder: the price a customer reads, in one place for the sign-up card and the package page.
	// With an introductory offer it leads with the intro price and says what follows; otherwise a yearly
	// price shows the twelve-month total struck through, what is saved, and the monthly equivalent. An offer
	// and a yearly saving never show together, so a price never carries two struck-through numbers.
	let {
		pkg,
		interval,
		size = 'card'
	}: { pkg: PublicPackage; interval: BillingInterval; size?: 'card' | 'hero' } = $props();

	const price = $derived(priceParts(pkg, interval));
	const offer = $derived(pkg.offers[interval]);
	const saving = $derived(interval === 'year' && !offer ? yearlySaving(pkg) : null);
</script>

<span class={`package-price package-price--${size}`}>
	{#if offer}
		<span class="package-price__badge">{offerHeadline(offer)}</span>
	{/if}
	<span class="package-price__line">
		{#if offer}
			<strong>{formatUsd(offer.intro_price_usd_cents)}</strong>
			<s class="package-price__was"
				><span class="package-price__hidden">Normally </span>{price.amount}</s
			>
		{:else if saving}
			<strong>{price.amount}</strong>
			<s class="package-price__was"
				><span class="package-price__hidden">Twelve monthly payments would be </span>{formatUsd(
					saving.twelveMonthsCents
				)}</s
			>
		{:else}
			<strong>{price.amount}</strong>
		{/if}
		<span class="package-price__per">{price.per}</span>
	</span>
	{#if offer}
		<span class="package-price__note">Then {price.amount} {price.per}</span>
	{:else if saving}
		<span class="package-price__note">
			That's {formatUsd(saving.perMonthCents)} a month
			<span class="package-price__save"
				>Save {formatUsd(saving.savedCents)} · {saving.percent}%</span
			>
		</span>
	{/if}
</span>

<style lang="scss">
	.package-price {
		display: grid;
		gap: var(--space-small);
		justify-items: start;
		font-variant-numeric: tabular-nums;

		&__badge,
		&__save {
			width: fit-content;
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-larger);
			color: var(--color-success--onSurface);
			background: var(--color-success--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			white-space: nowrap;
		}

		&__line {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-smaller) var(--space-small);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				line-height: 1.1;
				letter-spacing: -0.02em;
			}
		}

		&__was {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			text-decoration-thickness: 1px;
		}

		&__per {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		&--hero &__line strong {
			font-size: var(--typography--fontSize-jumbo);
			line-height: 1;
		}

		&--hero &__was {
			font-size: var(--typography--fontSize-large);
		}

		&--hero &__note {
			font-size: var(--typography--fontSize-base);
		}
	}
</style>
