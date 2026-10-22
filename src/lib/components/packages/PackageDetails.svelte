<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import PackagePrice from './PackagePrice.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import sparklesIcon from '@tabler/icons/outline/sparkles.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import appsIcon from '@tabler/icons/outline/apps.svg?raw';
	import gaugeIcon from '@tabler/icons/outline/gauge.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import minusIcon from '@tabler/icons/outline/circle-minus.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import globeIcon from '@tabler/icons/outline/world.svg?raw';
	import pinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import pipelineIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import marketingIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import {
		allowanceSentence,
		type BillingInterval,
		type PublicPackage
	} from '$lib/packages/public-package';

	let {
		pkg,
		interval,
		showHero = true
	}: { pkg: PublicPackage; interval: BillingInterval; showHero?: boolean } = $props();
	const Heading = $derived(showHero ? 'h3' : 'h2');
	const ItemHeading = $derived(showHero ? 'h4' : 'h3');
	const core = $derived(pkg.capabilities.filter((capability) => capability.core));
	const extras = $derived(pkg.capabilities.filter((capability) => !capability.core));
	const hasMonthlyReset = $derived(pkg.allowances.some((allowance) => allowance.resets_monthly));
	const prices = $derived(
		(['month', 'year'] as const).filter((option) =>
			option === 'month'
				? pkg.monthly_price_usd_cents !== null
				: pkg.yearly_price_usd_cents !== null
		)
	);
	const steps = [
		{ title: 'You apply', description: 'Pick a package and send this form.' },
		{ title: 'We send payment instructions', description: 'You pay us directly, outside the app.' },
		{ title: 'Your account starts', description: 'Once the first payment arrives.' }
	];
	// Public services have editable names, rather than service keys. Unknown names retain the section icon.
	function meaning(name: string) {
		const value = name.toLowerCase();
		if (/google|profile/.test(value)) return { icon: pinIcon, tone: 'review' };
		if (/review/.test(value)) return { icon: starIcon, tone: 'review' };
		if (/call|text|inbox|messag|chat/.test(value)) return { icon: phoneIcon, tone: 'conversation' };
		if (/website/.test(value)) return { icon: globeIcon, tone: 'growth' };
		if (/pipeline/.test(value)) return { icon: pipelineIcon, tone: 'growth' };
		if (/marketing|campaign/.test(value)) return { icon: marketingIcon, tone: 'growth' };
		return { icon: appsIcon, tone: 'inactive' };
	}
	function allowanceWords(allowance: PublicPackage['allowances'][number]) {
		return allowanceSentence(allowance).replace(/^(?:Up to )?[\d,]+ |^Unlimited /, '');
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet heading(title: string, icon: string, tone = 'inactive', hint?: string)}
	<div class="package-details__heading">
		<IconTile {icon} {tone} size={32} />
		<div>
			<svelte:element this={Heading}>{title}</svelte:element>
			{#if hint}<p>{hint}</p>{/if}
		</div>
	</div>
{/snippet}
{#snippet highlights()}
	{#if pkg.highlights.length}
		<ul class="package-details__checks">
			{#each pkg.highlights as highlight (highlight)}<li>
					<span aria-hidden="true">{@html circleCheckIcon}</span>{highlight}
				</li>{/each}
		</ul>
	{/if}
{/snippet}
<div class="package-details">
	{#if showHero}
		<section class="package-details__hero" aria-label="Plan summary">
			<div class="package-details__outcomes">
				{@render heading('What you get', sparklesIcon, 'feature')}{@render highlights()}
			</div>
			<div class="package-details__chosen">
				<p class="package-details__eyebrow">
					{interval === 'month' ? 'Monthly' : 'Yearly'} · Selected
				</p>
				<PackagePrice {pkg} {interval} onFeature />
			</div>
		</section>
	{:else if pkg.highlights.length}
		<section>
			{@render heading('What you get', sparklesIcon, 'growth')}{@render highlights()}
		</section>
	{/if}
	{#if pkg.included_services.length}
		<section>
			{@render heading(
				'Services we deliver',
				briefcaseIcon,
				'growth',
				'Uplift does this work for you.'
			)}
			<div class="package-details__services">
				{#each pkg.included_services as service (service.name)}
					{@const style = meaning(service.name)}
					<div class="package-details__service">
						<IconTile icon={style.icon} tone={style.tone} />
						<svelte:element this={ItemHeading}>{service.name}</svelte:element>
						{#if service.description}<p>{service.description}</p>{/if}
					</div>
				{/each}
			</div>
		</section>
	{/if}
	<div
		class={[
			'package-details__middle',
			{ 'package-details__middle--no-limits': !pkg.allowances.length }
		]}
	>
		<section class="package-details__panel">
			{@render heading('In the app', appsIcon)}
			{#if extras.length}<div class="package-details__features">
					{#each extras as capability (capability.key)}
						{@const style = meaning(capability.key + ' ' + capability.label)}
						<div class="package-details__feature">
							<IconTile icon={style.icon} tone={style.tone} size={32} />
							<div>
								<svelte:element this={ItemHeading}>{capability.label}</svelte:element>
								<p>{capability.description}</p>
							</div>
						</div>
					{/each}
				</div>{/if}
			{#if core.length}<p class="package-details__eyebrow">Included in every package</p>
				<ul class="package-details__basics">
					{#each core as capability (capability.key)}<li>{capability.label}</li>{/each}
				</ul>{/if}
		</section>
		{#if pkg.allowances.length}
			<section class="package-details__panel">
				{@render heading('Limits', gaugeIcon)}
				<dl class="package-details__limits">
					{#each pkg.allowances as allowance (allowance.key)}<div>
							<dt>{allowanceWords(allowance)}</dt>
							<dd>
								{allowance.state === 'unlimited'
									? 'Unlimited'
									: (allowance.value ?? 0).toLocaleString('en-US')}
							</dd>
						</div>{/each}
				</dl>
				{#if hasMonthlyReset}<p class="package-details__reset">
						<span aria-hidden="true">{@html refreshIcon}</span>Monthly amounts start fresh every
						month, including on yearly billing.
					</p>{/if}
			</section>
		{/if}
	</div>
	<section>
		{@render heading('Price and payment', creditCardIcon, 'invoice', 'Prices are in US dollars.')}
		<ul class="package-details__prices">
			{#each prices as option (option)}
				<li class={{ 'package-details__price--chosen': option === interval }}>
					<div class="package-details__billing">
						<span class="package-details__eyebrow">{option === 'month' ? 'Monthly' : 'Yearly'}</span
						>{#if option === interval}<span class="package-details__selected"
								><span aria-hidden="true">{@html checkIcon}</span>Selected</span
							>{/if}
					</div>
					<PackagePrice {pkg} interval={option} />
				</li>
			{/each}
		</ul>
		<div class="package-details__payment">
			<p class="package-details__eyebrow">How paying works</p>
			<ol>
				{#each steps as step, i (step.title)}<li>
						<span class="package-details__step">{i + 1}</span>
						<div>
							<svelte:element this={ItemHeading}>{step.title}</svelte:element>
							<p>{step.description}</p>
						</div>
					</li>{/each}
			</ol>
			<p>
				Text messages, and any email beyond the amounts above, are paid separately from a prepaid
				balance.
			</p>
		</div>
	</section>
	{#if pkg.exclusions}<section class="package-details__exclusions">
			<IconTile icon={minusIcon} white size={32} />
			<div>
				<svelte:element this={Heading}>Not included</svelte:element>
				<p>{pkg.exclusions}</p>
			</div>
		</section>{/if}
</div>

<style lang="scss">
	.package-details {
		display: grid;
		gap: var(--space-large);
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		overflow-wrap: anywhere;
		line-height: var(--typography--lineHeight-large);
		section,
		div {
			min-width: 0;
		}
		h2,
		h3,
		h4,
		p,
		ul,
		ol,
		dl,
		dd {
			margin: 0;
		}
		h2,
		h3,
		h4 {
			color: var(--color-heading);
			font-weight: 600;
		}
		h2,
		h3,
		h4 {
			font-size: var(--typography--fontSize-base);
		}
		h4 {
			font-size: var(--typography--fontSize-base);
		}
		p {
			color: var(--color-text--secondary);
			overflow-wrap: anywhere;
		}
		&__heading {
			:is(h2, h3) {
				font-size: var(--typography--fontSize-large);
			}
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			margin-bottom: var(--space-slim);
			p {
				font-size: var(--typography--fontSize-overline);
			}
		}
		&__hero {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 300px;
			align-items: start;
			gap: var(--space-large);
			padding: var(--space-large);
			border-radius: var(--radius-large);
			background:
				radial-gradient(
					ellipse at top right,
					var(--color-feature--glow),
					var(--color-feature--glow-end) 65%
				),
				linear-gradient(135deg, var(--color-feature--start), var(--color-feature--end));
			color: var(--color-feature--text);
		}
		&__hero &__heading :is(h2, h3) {
			color: var(--color-feature--text);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
		}
		&__checks {
			display: grid;
			gap: var(--space-slim);
			padding: 0;
			list-style: none;
			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-small);
				font-weight: 500;
			}
			span {
				display: flex;
				flex-shrink: 0;
				padding-top: var(--space-smallest);
			}
			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
		&__chosen {
			display: grid;
			gap: var(--space-slim);
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-large);
			padding: var(--space-medium);
			background: var(--color-feature--subtle);
		}
		&__eyebrow {
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: var(--typography--letterSpacing-loose);
		}
		&__chosen &__eyebrow {
			color: var(--color-feature--text--secondary);
		}
		&__services {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(min(100%, 180px), 1fr));
			gap: var(--space-slim);
		}
		&__service {
			display: grid;
			align-content: start;
			gap: var(--space-small);
			padding: var(--space-base);
			border-radius: calc(var(--radius-base) + var(--radius-small));
			background: var(--color-surface--background);
		}
		&__middle {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 280px;
			gap: var(--space-base);
		}
		&__middle--no-limits {
			grid-template-columns: minmax(0, 1fr);
		}
		&__panel {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: var(--space-base);
			border-radius: calc(var(--radius-base) + var(--radius-small));
			background: var(--color-surface--background);
			> .package-details__heading {
				margin-bottom: 0;
			}
		}
		&__features {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-small);
		}
		&__feature {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			p {
				font-size: var(--typography--fontSize-overline);
			}
		}
		&__basics {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			padding: 0;
			list-style: none;
			li {
				padding: var(--space-smaller) var(--space-slim);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-circle);
				color: var(--color-heading);
				background: var(--color-surface);
				font-weight: 500;
			}
		}
		&__limits {
			display: grid;
			gap: var(--space-small);
			> div {
				display: flex;
				flex-direction: column-reverse;
				padding: var(--space-small) var(--space-slim);
				border-radius: var(--radius-base);
				background: var(--color-surface);
			}
			dt {
				color: var(--color-text--secondary);
				font-weight: 500;
			}
			dd {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-display);
				font-weight: 700;
				letter-spacing: -0.6px;
			}
		}
		&__reset {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			font-size: var(--typography--fontSize-overline);
			span {
				display: flex;
				padding-top: var(--space-smallest);
			}
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__prices {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(min(100%, 240px), 1fr));
			gap: var(--space-slim);
			padding: 0;
			list-style: none;
			> li {
				display: grid;
				align-content: start;
				gap: var(--space-small);
				padding: var(--space-base);
				border: var(--border-base) solid var(--color-border);
				border-radius: calc(var(--radius-base) + var(--radius-small));
			}
		}
		&__price--chosen {
			border-color: var(--color-interactive) !important;
		}
		&__billing {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}
		&__selected {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-interactive);
			font-weight: 600;
			span {
				display: flex;
			}
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__payment {
			display: grid;
			gap: var(--space-slim);
			margin-top: var(--space-slim);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-invoice--surface-edge);
			border-radius: calc(var(--radius-base) + var(--radius-small));
			background: var(--color-invoice--surface);
			> p {
				color: var(--color-invoice--onSurface);
				font-size: var(--typography--fontSize-overline);
			}
			ol {
				display: grid;
				grid-template-columns: repeat(3, minmax(0, 1fr));
				gap: var(--space-small);
				padding: 0;
				list-style: none;
			}
			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-small);
				padding: var(--space-slim);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				p {
					font-size: var(--typography--fontSize-overline);
				}
			}
		}
		&__step {
			display: grid;
			flex: 0 0 28px;
			height: 28px;
			place-items: center;
			border-radius: var(--radius-circle);
			color: var(--color-white);
			background: var(--color-invoice);
			font-weight: 600;
		}
		&__exclusions {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
			padding: var(--space-slim);
			border-radius: var(--radius-large);
			background: var(--color-inactive--surface);
			p {
				white-space: pre-line;
				color: var(--color-inactive--onSurface);
			}
			:is(h2, h3) {
				font-size: var(--typography--fontSize-base);
			}
		}
		@media (max-width: 760px) {
			&__hero,
			&__middle {
				grid-template-columns: minmax(0, 1fr);
			}
			&__features,
			&__payment ol {
				grid-template-columns: minmax(0, 1fr);
			}
		}
	}
</style>
