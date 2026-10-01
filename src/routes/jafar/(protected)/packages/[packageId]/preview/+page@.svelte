<script lang="ts">
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import PackageCard from '$lib/components/packages/PackageCard.svelte';
	import PackageOfferPage from '$lib/components/packages/PackageOfferPage.svelte';
	import { offeredInterval, type BillingInterval } from '$lib/packages/public-package';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	// Both views render the components customers see: the card from /get-started and the details page.
	let view = $state<'card' | 'page'>('card');
	let wanted = $derived<BillingInterval>(data.billing);
	let group = $state('');
</script>

<svelte:head>
	<title>Preview · {data.pkg.name}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="package-preview">
	<header class="package-preview__bar">
		<span class="package-preview__badge">
			<span class="package-preview__icon" aria-hidden="true">{@html eyeIcon}</span>
			Preview
		</span>
		<p class="package-preview__note">
			{data.isDraft
				? 'This is your saved draft. Customers cannot see it until you publish it.'
				: 'This package has no draft, so this is its published edition.'}
		</p>
		<div class="package-preview__controls">
			<SegmentedControl
				bind:value={view}
				size="small"
				label="Preview view"
				options={[
					{ value: 'card', label: 'Sign-up card' },
					{ value: 'page', label: 'Details page' }
				]}
			/>
		</div>
	</header>

	{#if view === 'card'}
		<main class="package-preview__stage">
			<h1 class="package-preview__title">How it looks when a customer chooses a package</h1>
			{#if data.pkg.monthly_price_usd_cents !== null && data.pkg.yearly_price_usd_cents !== null}
				<SegmentedControl
					bind:value={wanted}
					size="small"
					label="Billing"
					options={[
						{ value: 'month', label: 'Monthly' },
						{ value: 'year', label: 'Yearly' }
					]}
				/>
			{/if}
			<div class="package-preview__card">
				<PackageCard
					pkg={data.pkg}
					{wanted}
					interval={offeredInterval(data.pkg, wanted)}
					selected={group === data.pkg.edition_id}
					bind:group
					onviewdetails={() => (view = 'page')}
				/>
			</div>
		</main>
	{:else}
		<main>
			<PackageOfferPage pkg={data.pkg} billing={wanted} preview />
		</main>
	{/if}
</div>

<style lang="scss">
	.package-preview {
		min-height: 100vh;
		background: var(--color-surface--background);

		&__bar {
			position: sticky;
			top: 0;
			z-index: 10;
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-small) var(--space-large);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface);
		}

		&__badge {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__note {
			flex: 1 1 240px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__controls {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__stage {
			display: grid;
			justify-items: center;
			gap: var(--space-large);
			max-width: 420px;
			margin: 0 auto;
			padding: var(--space-largest) var(--space-base);
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			text-align: center;
		}

		&__card {
			width: 100%;
		}
	}
</style>
