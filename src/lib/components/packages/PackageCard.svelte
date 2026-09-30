<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import {
		priceParts,
		type BillingInterval,
		type PublicPackage
	} from '$lib/packages/public-package';

	// Package builder P9: one choosable package on /get-started — name, the exact price for the billing the
	// visitor picked, its promise, and up to six highlights. "View details" opens the full terms without
	// choosing or leaving the form.
	let {
		pkg,
		interval,
		wanted,
		selected,
		group = $bindable(),
		onviewdetails
	}: {
		pkg: PublicPackage;
		/** The billing this package is offered on: `wanted` when it has that price, otherwise the other. */
		interval: BillingInterval;
		wanted: BillingInterval;
		selected: boolean;
		group: string;
		onviewdetails: () => void;
	} = $props();

	const price = $derived(priceParts(pkg, interval));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="package-card" class:package-card--selected={selected}>
	<label class="package-card__choose">
		<input
			type="radio"
			name="package_edition_id"
			value={pkg.edition_id}
			bind:group
			class="package-card__radio"
		/>
		<span class="package-card__top">
			<span class="package-card__name">{pkg.name}</span>
			{#if selected}<span class="package-card__selected">Selected</span>{/if}
		</span>
		<span class="package-card__price">
			<strong>{price.amount}</strong>
			<span>{price.per}</span>
		</span>
		{#if interval !== wanted}
			<span class="package-card__interval-note">
				Only offered {interval === 'month' ? 'monthly' : 'yearly'}
			</span>
		{/if}
		{#if pkg.promise}<span class="package-card__promise">{pkg.promise}</span>{/if}
		{#if pkg.highlights.length}
			<span class="package-card__highlights">
				{#each pkg.highlights.slice(0, 6) as highlight (highlight)}
					<span class="package-card__highlight">
						<span class="package-card__check" aria-hidden="true">{@html checkIcon}</span>
						{highlight}
					</span>
				{/each}
			</span>
		{/if}
	</label>
	<button type="button" class="package-card__details" onclick={onviewdetails}>
		View details
	</button>
</div>

<style lang="scss">
	.package-card {
		position: relative;
		display: flex;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition:
			border-color var(--timing-quick) ease-out,
			box-shadow var(--timing-quick) ease-out;

		&:hover {
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-low);
		}

		&:has(.package-card__radio:focus-visible),
		&--selected {
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-focus);
		}

		&__choose {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-large) var(--space-large) var(--space-base);
			cursor: pointer;
		}

		&__radio {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
		}

		&__top {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		&__selected {
			padding: var(--space-smaller) var(--space-small);
			border-radius: var(--radius-larger);
			color: var(--color-success--onSurface);
			background: var(--color-success--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 700;
		}

		&__price {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-smaller);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				line-height: 1.1;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__interval-note {
			width: fit-content;
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}

		&__promise {
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-large);
		}

		&__highlights {
			display: grid;
			gap: var(--space-small);
			margin-top: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__highlight {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			color: var(--color-text);
			line-height: var(--typography--lineHeight-large);
		}

		&__check {
			display: inline-flex;
			flex: 0 0 16px;
			width: 16px;
			height: 16px;
			margin-top: 3px;
			color: var(--color-success);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__details {
			margin: 0 var(--space-large) var(--space-large);
			padding: var(--space-small) 0 0;
			border: 0;
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-weight: 600;
			text-align: left;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
