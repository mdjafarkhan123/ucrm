<script lang="ts">
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import PackageDetails from '$lib/components/packages/PackageDetails.svelte';
	import { formatUsd } from '$lib/jafar/packages';
	import {
		offerHeadline,
		offeredInterval,
		offersBoth,
		priceParts,
		yearlySavingPercent,
		type BillingInterval,
		type PublicPackage
	} from '$lib/packages/public-package';

	// Package builder P9: the whole page a customer reads for one package. The public /packages/[slug] page
	// and Jafar's draft preview both render this one component, so what he previews is what customers see.
	// In a preview the Apply buttons do nothing, since nobody can apply to a draft.
	let {
		pkg,
		billing,
		preview = false
	}: { pkg: PublicPackage | null; billing: BillingInterval; preview?: boolean } = $props();

	// Starts from the link's billing choice; the visitor can switch it.
	let wanted = $derived<BillingInterval>(billing);
	const interval = $derived(pkg ? offeredInterval(pkg, wanted) : 'month');
	const price = $derived(pkg ? priceParts(pkg, interval) : null);
	const saving = $derived(pkg ? yearlySavingPercent(pkg) : null);
	const offer = $derived(pkg ? pkg.offers[interval] : null);
	const applyHref = $derived(
		pkg
			? `${resolve('/get-started')}?package=${encodeURIComponent(pkg.slug)}&billing=${interval}`
			: resolve('/get-started')
	);
</script>

<div class="package-page">
	<div class="package-page__inner">
		<header class="package-page__brand">
			<span class="package-page__brand-mark">U</span> UpliftContractor
		</header>

		{#if pkg && price}
			<section class="package-page__hero">
				<div>
					<p class="package-page__eyebrow">Package</p>
					<h1>{pkg.name}</h1>
					{#if pkg.promise}<p class="package-page__promise">{pkg.promise}</p>{/if}
				</div>
				<div class="package-page__offer">
					{#if offersBoth(pkg)}
						<SegmentedControl
							bind:value={wanted}
							size="small"
							options={[
								{ value: 'month', label: 'Monthly' },
								{ value: 'year', label: saving ? `Yearly · save ${saving}%` : 'Yearly' }
							]}
						/>
					{/if}
					{#if offer}
						<p class="package-page__price">
							<em class="package-page__offer-name">{offerHeadline(offer)}</em>
							<strong>{formatUsd(offer.intro_price_usd_cents)}</strong>
							<span>Then {price.amount} {price.per}</span>
						</p>
					{:else}
						<p class="package-page__price">
							<strong>{price.amount}</strong>
							<span>{price.per}</span>
						</p>
					{/if}
					<Button href={preview ? undefined : applyHref} disabled={preview} fullWidth
						>Apply for {pkg.name}</Button
					>
				</div>
			</section>

			<PackageDetails {pkg} {interval} />

			<footer class="package-page__footer">
				<Button href={preview ? undefined : applyHref} disabled={preview}
					>Apply for {pkg.name}</Button
				>
				{#if !preview}<a href={resolve('/get-started')}>Compare all packages</a>{/if}
			</footer>
		{:else}
			<section class="package-page__missing">
				<h1>This package isn’t available</h1>
				<p>
					It may have been replaced or is no longer offered. See the packages open for sign-up now
					and choose the one that fits.
				</p>
				<Button href={resolve('/get-started')}>See current packages</Button>
			</section>
		{/if}
	</div>
</div>

<style lang="scss">
	.package-page {
		min-height: 100vh;
		padding: var(--space-largest) var(--space-base);
		color: var(--color-text);
		background: var(--color-surface--background);

		&__inner {
			display: grid;
			gap: var(--space-largest);
			max-width: 880px;
			margin: 0 auto;
			padding: var(--space-largest);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			box-shadow: var(--shadow-base);
		}

		&__brand {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-heading);
			font-weight: 700;
		}

		&__brand-mark {
			display: grid;
			width: 32px;
			height: 32px;
			place-items: center;
			border-radius: var(--radius-small);
			color: var(--color-surface);
			background: var(--color-interactive);
			font-weight: 900;
		}

		&__hero {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 300px;
			gap: var(--space-largest);
			align-items: start;

			h1 {
				margin: var(--space-smaller) 0 var(--space-small);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-jumbo);
				line-height: var(--typography--lineHeight-minuscule);
			}
		}

		&__eyebrow {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;
		}

		&__promise {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-large);
			line-height: var(--typography--lineHeight-large);
		}

		&__offer {
			display: grid;
			gap: var(--space-base);
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__offer-name {
			width: fit-content;
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-success--onSurface);
			background: var(--color-success--surface);
			font-size: var(--typography--fontSize-small);
			font-style: normal;
			font-weight: 700;
		}

		&__price {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-jumbo);
				line-height: 1;
			}

			span {
				color: var(--color-text--secondary);
			}
		}

		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-large);
			padding-top: var(--space-large);
			border-top: var(--border-base) solid var(--color-border);

			a {
				color: var(--color-interactive);
			}
		}

		&__missing {
			display: grid;
			gap: var(--space-base);
			justify-items: start;

			h1 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
				line-height: var(--typography--lineHeight-large);
			}
		}

		@media (max-width: 720px) {
			padding: 0;

			&__inner {
				gap: var(--space-large);
				padding: var(--space-large) var(--space-base);
				border: 0;
				border-radius: 0;
				box-shadow: none;
			}

			&__hero {
				grid-template-columns: 1fr;
				gap: var(--space-large);

				h1 {
					font-size: var(--typography--fontSize-largest);
				}
			}
		}
	}
</style>
