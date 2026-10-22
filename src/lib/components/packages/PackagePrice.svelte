<script lang="ts">
	import discountIcon from '@tabler/icons/outline/discount.svg?raw';
	import savingIcon from '@tabler/icons/outline/pig-money.svg?raw';
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
		size = 'card',
		onFeature = false
	}: {
		pkg: PublicPackage;
		interval: BillingInterval;
		size?: 'card' | 'hero';
		onFeature?: boolean;
	} = $props();

	const price = $derived(priceParts(pkg, interval));
	const offer = $derived(pkg.offers[interval]);
	const saving = $derived(interval === 'year' && !offer ? yearlySaving(pkg) : null);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span class={[`package-price package-price--${size}`, { 'package-price--feature': onFeature }]}>
	{#if offer}
		<span class="package-price__badge"
			><span aria-hidden="true">{@html discountIcon}</span>{offerHeadline(offer)}</span
		>
	{:else if saving}
		<span class="package-price__badge"
			><span aria-hidden="true">{@html savingIcon}</span>Save {formatUsd(saving.savedCents)} · {saving.percent}%</span
		>
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
		<span class="package-price__note"
			><b>Then {price.amount} {price.per}</b>
			{#if offer.claim_ends_at}<span
					>Join by {new Date(offer.claim_ends_at).toLocaleDateString('en-US', {
						month: 'long',
						day: 'numeric',
						year: 'numeric'
					})} to get it.</span
				>{:else if interval === 'year'}<span>Paid upfront</span>{/if}
		</span>
	{:else if saving}
		<span class="package-price__note">
			<b>That's {formatUsd(saving.perMonthCents)} a month</b>
			<span>Paid upfront</span>
		</span>
	{/if}
</span>

<style lang="scss">
	.package-price {
		display: grid;
		gap: var(--space-small);
		justify-items: start;
		font-variant-numeric: tabular-nums;

		&__badge {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			> span {
				display: flex;
				flex: 0 0 auto;
			}
			:global(svg) {
				width: 14px;
				height: 14px;
			}
			width: fit-content;
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-larger);
			color: var(--color-success--onSurface);
			background: var(--color-success--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			max-width: 100%;
			white-space: normal;
		}

		&__line {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-smaller) var(--space-small);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-display);
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
			display: grid;
			gap: var(--space-smaller);
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-overline);
			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}
		&--feature {
			.package-price__badge {
				background: var(--color-feature--text);
				color: var(--color-feature--start);
			}
			.package-price__line strong,
			.package-price__note b {
				color: var(--color-feature--text);
			}
			.package-price__was,
			.package-price__per,
			.package-price__note {
				color: var(--color-feature--text--secondary);
			}
			.package-price__note {
				background: var(--color-feature--subtle);
			}
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
			font-size: var(--typography--fontSize-extravagant);
			line-height: 1;
		}

		&--hero &__was {
			font-size: var(--typography--fontSize-base);
		}

		&--hero &__note {
			font-size: var(--typography--fontSize-base);
		}
	}
</style>
