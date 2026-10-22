<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import NextSteps from './NextSteps.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		formatMinor,
		formatPhone,
		numberTypeLabel,
		type NumberKind,
		type ShopNumber
	} from '$lib/communications/sms-number-shop';
	import { kindIcon, nextSteps, placeLine } from './add-number';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';

	// Step 3 of Add number (`concept.pen` board `qaFQf`): the bill, read back before anything is charged. "Paid from"
	// turns red when the bought balance can't cover today's charge (the rule from Charges before sending, `nLAe4`).
	let {
		countryCode,
		number,
		kind,
		balanceMinor,
		checking,
		refusal,
		onPickAnother
	}: {
		countryCode: string;
		number: ShopNumber;
		kind: NumberKind;
		balanceMinor: number;
		checking: boolean;
		refusal: { code: string | null; message: string } | null;
		onPickAnother: () => void;
	} = $props();

	let countryName = $derived(countryDisplayName(countryCode));
	let paperworkFirst = $derived(kind.needs === 'paperwork_first');
	let monthly = $derived(kind.monthly_minor ?? 0);
	let setup = $derived(kind.setup_minor ?? 0);
	let today = $derived(monthly + setup);
	let short = $derived(balanceMinor < today);
	let money = (minor: number) => formatMinor(minor, kind.currency_code);
	let shortName = $derived(countryCode === 'US' ? 'the US' : countryName);

	const abilities = [
		{ key: 'sms', icon: messageIcon, label: 'Text' },
		{ key: 'mms', icon: photoIcon, label: 'Pictures' },
		{ key: 'voice', icon: phoneIcon, label: 'Calls' }
	] as const;
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="add-number-bill">
	{#if checking}
		<div class="add-number-bill__checking" role="status">
			<span class="add-number-bill__spinner" aria-hidden="true">{@html loaderIcon}</span>
			<p>
				The connection dropped while buying. We’re asking the phone company whether {formatPhone(
					number.phone_number
				)} is yours now. You will never be charged twice.
			</p>
		</div>
	{/if}

	{#if refusal}
		<Banner type="error">
			{refusal.message}
			{#snippet action()}
				{#if refusal.code === 'insufficient_balance'}
					<Button variant="secondary" size="small" href="/settings/communications/balance">
						Add credit
					</Button>
				{:else if refusal.code === 'number_unavailable' || refusal.code === 'number_being_bought' || refusal.code === 'twilio_rejected'}
					<Button variant="secondary" size="small" onclick={onPickAnother}>
						Pick another number
					</Button>
				{/if}
			{/snippet}
		</Banner>
	{/if}

	<header class="add-number-bill__head">
		<h3>Check and buy</h3>
		<p>
			{#if paperworkFirst}
				{countryName} needs approved paperwork before this number can be bought.
			{:else}
				Nothing is charged until you press Buy.
			{/if}
		</p>
	</header>

	<section class="bill" aria-label="The bill">
		<div class="bill__band">
			<IconTile icon={kindIcon(kind.number_type)} tone="conversation" white />
			<div class="bill__who">
				<strong>{formatPhone(number.phone_number)}</strong>
				<span>
					{placeLine(
						number.locality,
						number.region ?? countryName,
						`${numberTypeLabel(kind.number_type)} number`
					)}
				</span>
			</div>
			<ul class="bill__abilities" aria-label="What it can do">
				{#each abilities.filter((ability) => number.capabilities[ability.key]) as ability (ability.key)}
					<li><span aria-hidden="true">{@html ability.icon}</span>{ability.label}</li>
				{/each}
			</ul>
		</div>
		<dl class="bill__lines">
			<div>
				<dt>Paperwork</dt>
				<dd>
					{#if paperworkFirst}
						<StatusBadge status="warning">Needed first</StatusBadge>
					{:else}
						<StatusBadge status="success">Not needed in {shortName}</StatusBadge>
					{/if}
				</dd>
			</div>
			<div class="bill__total">
				<dt>{paperworkFirst ? 'When you buy' : 'Today'}</dt>
				<dd>
					<span class="bill__quiet">{setup > 0 ? 'First month + setup' : 'First month'}</span>
					<strong>{money(today)}</strong>
				</dd>
			</div>
			<div>
				<dt>Every month after</dt>
				<dd><strong>{money(monthly)}</strong></dd>
			</div>
			<div>
				<dt>Setup charge</dt>
				<dd>
					{#if setup > 0}
						<span class="bill__quiet">One time</span>
						<strong>{money(setup)}</strong>
					{:else}
						<strong>None</strong>
					{/if}
				</dd>
			</div>
			<div class:bill__short={short}>
				<dt>Paid from</dt>
				<dd>
					<span class="bill__quiet">{money(balanceMinor)} left</span>
					<strong>Texting balance</strong>
				</dd>
			</div>
		</dl>
	</section>

	{#if paperworkFirst}
		<Banner type="warning">
			Numbers aren’t held while the paperwork is checked. Once it’s approved, you pick from the
			numbers free at that time.
		</Banner>
	{:else if short && !refusal}
		<Banner type="error">
			Your texting balance has {money(balanceMinor)} left, and this number needs {money(today)} today.
			{#snippet action()}
				<Button variant="secondary" size="small" href="/settings/communications/balance">
					Add credit
				</Button>
			{/snippet}
		</Banner>
	{/if}

	<NextSteps
		steps={nextSteps({
			countryCode,
			numberType: kind.number_type,
			paperworkFirst,
			bought: false
		})}
	/>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.add-number-bill {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__head {
			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}

			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}
		}

		&__checking {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim);
			border-radius: var(--radius-large);
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);

			p {
				margin: 0;
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
				line-height: 1.45;
			}
		}

		&__spinner {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-informative);

			:global(svg) {
				width: 16px;
				height: 16px;
				animation: add-number-spin 0.9s linear infinite;
			}
		}
	}

	@keyframes add-number-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.add-number-bill__spinner :global(svg) {
			animation: none;
		}
	}

	.bill {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__band {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-conversation--surface-edge);
			background: var(--color-conversation--surface);
		}

		&__who {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				letter-spacing: -0.02em;
			}

			span {
				color: var(--color-conversation--onSurface);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
			}
		}

		&__abilities {
			display: flex;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: inline-flex;
				align-items: center;
				gap: var(--space-smaller);
				height: 24px;
				padding: 0 var(--space-small);
				border-radius: var(--radius-circle);
				background: var(--color-surface);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 600;
			}

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}

		&__lines {
			margin: 0;
			padding: 0 var(--space-base);

			> div {
				display: flex;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-base);
				padding: var(--space-slim) 0;

				& + div {
					border-top: var(--border-base) solid var(--color-border);
				}
			}

			dt {
				color: var(--color-text);
				font-size: var(--typography--fontSize-base);
			}

			dd {
				display: flex;
				align-items: baseline;
				gap: var(--space-slim);
				margin: 0;

				strong {
					color: var(--color-heading);
					font-size: var(--typography--fontSize-base);
					font-weight: 600;
				}
			}
		}

		&__total dd strong {
			font-weight: 700;
		}

		&__quiet {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__short dd,
		&__short dd strong,
		&__short .bill__quiet {
			color: var(--color-critical--onSurface);
		}
	}
</style>
