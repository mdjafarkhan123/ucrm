<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import sparklesIcon from '@tabler/icons/outline/sparkles.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import appsIcon from '@tabler/icons/outline/apps.svg?raw';
	import gaugeIcon from '@tabler/icons/outline/gauge.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import {
		allowanceSentence,
		priceSentence,
		yearlySavingPercent,
		type BillingInterval,
		type PublicPackage
	} from '$lib/packages/public-package';

	// Package builder P9: the full terms of one published edition — outcomes first, then exactly what is
	// included, its limits, what is not included, and how payment works. Shown in the /get-started dialog
	// and on the package's own page, so both always say the same thing.
	let { pkg, interval }: { pkg: PublicPackage; interval: BillingInterval } = $props();

	const core = $derived(pkg.capabilities.filter((capability) => capability.core));
	const extras = $derived(pkg.capabilities.filter((capability) => !capability.core));
	const saving = $derived(yearlySavingPercent(pkg));
	const hasMonthlyReset = $derived(pkg.allowances.some((allowance) => allowance.resets_monthly));
	const prices = $derived(
		(['month', 'year'] as const).filter((option) =>
			option === 'month'
				? pkg.monthly_price_usd_cents !== null
				: pkg.yearly_price_usd_cents !== null
		)
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="package-details">
	{#if pkg.highlights.length}
		<SectionBlock title="What you get" icon={sparklesIcon} level={3}>
			<ul class="package-details__checks">
				{#each pkg.highlights as highlight (highlight)}
					<li><span aria-hidden="true">{@html checkIcon}</span>{highlight}</li>
				{/each}
			</ul>
		</SectionBlock>
	{/if}

	{#if pkg.included_services.length}
		<SectionBlock title="Services we deliver" icon={briefcaseIcon} level={3}>
			<dl class="package-details__items">
				{#each pkg.included_services as service (service.name)}
					<div>
						<dt>{service.name}</dt>
						{#if service.description}<dd>{service.description}</dd>{/if}
					</div>
				{/each}
			</dl>
		</SectionBlock>
	{/if}

	<SectionBlock title="In the app" icon={appsIcon} level={3}>
		{#if extras.length}
			<dl class="package-details__items">
				{#each extras as capability (capability.key)}
					<div>
						<dt>{capability.label}</dt>
						<dd>{capability.description}</dd>
					</div>
				{/each}
			</dl>
		{/if}
		{#if core.length}
			<div class="package-details__core" class:package-details__core--after={extras.length > 0}>
				<p class="package-details__subhead">Included in every package</p>
				<p class="package-details__core-list">
					{core.map((capability) => capability.label).join(' · ')}
				</p>
			</div>
		{/if}
	</SectionBlock>

	{#if pkg.allowances.length}
		<SectionBlock
			title="Limits"
			icon={gaugeIcon}
			level={3}
			hint={hasMonthlyReset
				? 'Monthly amounts start fresh every month, including on yearly billing.'
				: undefined}
		>
			<ul class="package-details__checks">
				{#each pkg.allowances as allowance (allowance.key)}
					<li><span aria-hidden="true">{@html checkIcon}</span>{allowanceSentence(allowance)}</li>
				{/each}
			</ul>
		</SectionBlock>
	{/if}

	{#if pkg.exclusions}
		<SectionBlock title="Not included" icon={alertIcon} level={3}>
			<p class="package-details__text">{pkg.exclusions}</p>
		</SectionBlock>
	{/if}

	<SectionBlock title="Price and payment" icon={creditCardIcon} level={3}>
		<ul class="package-details__prices">
			{#each prices as option (option)}
				<li class:package-details__price--chosen={option === interval}>
					<span>{option === 'month' ? 'Monthly' : 'Yearly'}</span>
					<strong>{priceSentence(pkg, option)}</strong>
					{#if option === 'year' && saving}<em>Save {saving}% compared with monthly</em>{/if}
				</li>
			{/each}
		</ul>
		<p class="package-details__text">
			Prices are in US dollars. You pay us directly, outside the app — we send payment instructions
			after you apply, and your account starts once the first payment arrives. Text messages, and
			any email beyond the amounts above, are paid separately from a prepaid balance.
		</p>
	</SectionBlock>
</div>

<style lang="scss">
	.package-details {
		display: grid;
		gap: var(--space-large);

		&__checks {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-small);
				color: var(--color-text);
				line-height: var(--typography--lineHeight-large);
			}

			span {
				display: inline-flex;
				flex: 0 0 18px;
				width: 18px;
				height: 18px;
				margin-top: 2px;
				color: var(--color-success);

				:global(svg) {
					width: 18px;
					height: 18px;
				}
			}
		}

		&__items {
			display: grid;
			gap: var(--space-base);
			margin: 0;

			dt {
				color: var(--color-heading);
				font-weight: 600;
			}

			dd {
				margin: var(--space-smallest) 0 0;
				color: var(--color-text--secondary);
				line-height: var(--typography--lineHeight-large);
			}
		}

		&__core--after {
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__subhead {
			margin: 0 0 var(--space-smaller);
			color: var(--color-heading);
			font-weight: 600;
		}

		&__core-list,
		&__text {
			margin: 0;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-large);
			white-space: pre-line;
		}

		&__prices {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: grid;
				gap: var(--space-smallest);
				padding: var(--space-base);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			strong {
				color: var(--color-heading);
			}

			em {
				color: var(--color-success--onSurface, var(--color-success));
				font-size: var(--typography--fontSize-small);
				font-style: normal;
				font-weight: 600;
			}
		}

		&__price--chosen {
			border-color: var(--color-interactive) !important;
			box-shadow: var(--shadow-focus);
		}
	}
</style>
