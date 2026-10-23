<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import CountryBox from './CountryBox.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import type { ReadinessNumber } from '$lib/communications/number-readiness';
	import {
		fetchTextingCountries,
		formatRate,
		numberBand,
		requestTextingCountry,
		textingCountriesKey,
		type Destination
	} from '$lib/communications/sms-destinations';
	import globeIcon from '@tabler/icons/outline/world.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import photoOffIcon from '@tabler/icons/outline/photo-off.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import deviceMobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';

	// "Text customers in another country" (`concept.pen` board `xGLYB`, Approved A, Jafar 2026-10-23). The
	// business picks a country, sees what texting there costs and whether one of its numbers can text it, and
	// asks Uplift to switch it on. Uplift does it by hand in Twilio (GoHighLevel's support asks the same way),
	// so the country then shows Setting up under Where you can text.
	let {
		open,
		numbers,
		onClose
	}: {
		open: boolean;
		/** The business's numbers, to say which one would text the country. */
		numbers: ReadinessNumber[];
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const countriesQuery = createQuery(() => ({
		queryKey: textingCountriesKey,
		queryFn: fetchTextingCountries,
		staleTime: 60_000,
		enabled: open
	}));

	let country = $state('');
	let asked = $state<Destination | null>(null);

	const ask = createMutation(() => ({
		mutationFn: (code: string) => requestTextingCountry(code),
		onSuccess: async (destination) => {
			asked = destination;
			await queryClient.invalidateQueries({ queryKey: ['settings', 'communications', 'sms'] });
		}
	}));

	let data = $derived(countriesQuery.data);
	let prices = $derived(new Map((data?.prices ?? []).map((row) => [row.country, row])));
	let notOffered = $derived(new Set(data?.not_offered ?? []));
	let already = $derived((data?.destinations ?? []).filter((row) => row.status !== 'off'));
	let price = $derived(country ? prices.get(country) : undefined);
	let name = $derived(country ? countryDisplayName(country) : '');
	let band = $derived(country ? numberBand(numbers, country) : null);
	let asking = $derived(ask.isPending);

	let costs = $derived.by(() => {
		const currency = price?.currency ?? 'USD';
		const money = (amount: number | null | undefined) =>
			amount == null ? null : formatRate(amount, currency);
		const text = money(price?.segment);
		const picture = money(price?.mms);
		return [
			{ key: 'text', icon: messageIcon, label: 'A text', value: text, unit: 'up to 160 letters' },
			picture
				? {
						key: 'pictures',
						icon: photoIcon,
						label: 'Pictures',
						value: picture,
						unit: 'sent as pictures'
					}
				: text
					? {
							key: 'pictures',
							icon: photoOffIcon,
							label: 'Pictures',
							value: 'Words only',
							unit: 'no pictures there'
						}
					: { key: 'pictures', icon: photoIcon, label: 'Pictures', value: null, unit: '' },
			{
				key: 'number',
				icon: phoneIcon,
				label: 'A number',
				value: money(price?.number_monthly),
				unit: 'a month'
			}
		];
	});

	let steps = $derived([
		{ key: 'ask', tone: 'informative', icon: sendIcon, title: 'You ask', line: 'Today' },
		{
			key: 'switch',
			tone: 'warning',
			icon: hourglassIcon,
			title: 'Uplift switches it on',
			line: 'Shows Setting up'
		},
		{
			key: 'text',
			tone: 'success',
			icon: circleCheckIcon,
			title: name ? `You text ${name}` : 'You text them',
			line: 'We let you know'
		}
	]);

	function submit() {
		if (!country || asking) return;
		ask.mutate(country);
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title={asked ? `${name} is on its way` : 'Text customers in another country'}
	subtitle={asked ? undefined : 'Uplift switches it on for you, usually within one working day'}
	icon={globeIcon}
	iconTone="conversation"
	bare={Boolean(asked)}
	closeDisabled={asking}
	{onClose}
>
	{#if asked}
		<div class="ask-country__done">
			<IconTile icon={circleCheckIcon} tone="success" />
			<p class="ask-country__done-title" aria-hidden="true">{name} is on its way</p>
			<StatusBadge status={asked.status === 'ready' ? 'success' : 'warning'}>
				{asked.status === 'ready' ? 'Ready' : 'Setting up'}
			</StatusBadge>
			<p class="ask-country__done-line">
				{#if asked.status === 'ready'}
					Texting to {name} is already switched on. It shows as Ready under Where you can text.
				{:else}
					Uplift switches texting on for {name}, usually within one working day. It shows as Ready
					under Where you can text, and we’ll let you know.
				{/if}
			</p>
			{#if band?.tone === 'warning'}
				<div class="ask-country__band ask-country__band--warning ask-country__band--short">
					<IconTile icon={deviceMobileIcon} tone="warning" size={32} white />
					<strong>Then add a number in {name} to text from</strong>
				</div>
			{/if}
		</div>
	{:else}
		<div class="ask-country">
			{#if ask.isError}
				<Banner type="error">{ask.error?.message}</Banner>
			{/if}

			<div class="ask-country__block">
				<p class="ask-country__question" id="ask-country-label">Which country?</p>
				<CountryBox
					id="ask-country"
					labelledby="ask-country-label"
					bind:value={country}
					{already}
					{prices}
					{notOffered}
					loading={countriesQuery.isPending}
					disabled={asking}
				/>
				{#if countriesQuery.isError}
					<p class="ask-country__failed" role="alert">
						The countries couldn’t load.
						<button type="button" onclick={() => countriesQuery.refetch()}>Try again</button>
					</p>
				{/if}
			</div>

			{#if country}
				<section class="ask-country__block" aria-labelledby="ask-country-costs">
					<h3 class="ask-country__head" id="ask-country-costs">What it costs</h3>
					<div class="ask-country__costs">
						{#each costs as cost (cost.key)}
							<div class="ask-country__cost">
								<span class="ask-country__cost-label">
									<span class="ask-country__cost-icon" aria-hidden="true">{@html cost.icon}</span>
									{cost.label}
								</span>
								{#if cost.value}
									<span class="ask-country__cost-value"
										><strong>{cost.value}</strong> <small>{cost.unit}</small></span
									>
								{:else}
									<span class="ask-country__cost-value ask-country__cost-value--coming"
										>Price coming</span
									>
								{/if}
							</div>
						{/each}
					</div>
				</section>

				{#if band}
					<section class="ask-country__block" aria-labelledby="ask-country-number">
						<h3 class="ask-country__head" id="ask-country-number">Which number texts them</h3>
						<div class="ask-country__band ask-country__band--{band.tone}">
							<IconTile
								icon={band.tone === 'success' ? circleCheckIcon : deviceMobileIcon}
								tone={band.tone}
								size={32}
								white
							/>
							<span>
								<strong>{band.title}</strong>
								<span>{band.line}</span>
							</span>
						</div>
					</section>
				{/if}
			{/if}

			<section class="ask-country__block" aria-labelledby="ask-country-next">
				<h3 class="ask-country__head" id="ask-country-next">What happens next</h3>
				<ol class="ask-country__steps">
					{#each steps as step, index (step.key)}
						{#if index > 0}
							<li class="ask-country__arrow" aria-hidden="true">{@html chevronRightIcon}</li>
						{/if}
						<li class="ask-country__step">
							<span
								class="ask-country__step-tile ask-country__step-tile--{step.tone}"
								aria-hidden="true">{@html step.icon}</span
							>
							<span>
								<strong>{step.title}</strong>
								<span>{step.line}</span>
							</span>
						</li>
					{/each}
				</ol>
			</section>
		</div>
	{/if}

	{#snippet footer()}
		{#if asked}
			<Button onclick={onClose}>
				<span aria-hidden="true">{@html checkIcon}</span>
				Done
			</Button>
		{:else}
			<div class="ask-country__actions">
				<Button variant="secondary" disabled={asking} onclick={onClose}>Cancel</Button>
				<Button loading={asking} disabled={!country} onclick={submit}>
					<span aria-hidden="true">{@html sendIcon}</span>
					Ask Uplift to switch it on
				</Button>
			</div>
		{/if}
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.ask-country {
		display: grid;
		gap: var(--space-large);

		&__block {
			display: grid;
			gap: var(--space-small);
		}

		&__question {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__head {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__failed {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-smaller);

			button {
				padding: 0;
				border: 0;
				color: var(--color-interactive);
				background: transparent;
				font: inherit;
				font-weight: 600;
				cursor: pointer;
			}
		}

		&__costs {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-small);
		}

		&__cost {
			display: grid;
			gap: 6px;
			min-width: 0;
			padding: var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);
		}

		&__cost-label {
			display: flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__cost-icon,
		&__cost-icon :global(svg) {
			display: block;
			width: 14px;
			height: 14px;
			color: var(--color-conversation);
		}

		&__cost-value {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
			}

			small {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}

			&--coming {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__band {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) 14px;
			border-radius: var(--radius-tile-large);

			> span {
				display: grid;
				gap: 2px;
			}

			strong {
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span span {
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}

			&--warning {
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}

			&--success {
				color: var(--color-success--onSurface);
				background: var(--color-success--surface);
			}
		}

		&__steps {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__step {
			display: flex;
			flex: 1 1 0;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;

			> span:last-child {
				display: grid;
				gap: 2px;
				min-width: 0;
			}

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 600;
			}

			span span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__step-tile {
			display: grid;
			flex: 0 0 28px;
			width: 28px;
			height: 28px;
			place-items: center;
			border-radius: var(--radius-circle);

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			&--informative {
				color: var(--color-informative);
				background: var(--color-informative--surface);
			}

			&--warning {
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}

			&--success {
				color: var(--color-success);
				background: var(--color-success--surface);
			}
		}

		&__arrow,
		&__arrow :global(svg) {
			display: block;
			flex: none;
			width: 14px;
			height: 14px;
			color: var(--color-icon--secondary);
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}

		&__done {
			display: grid;
			justify-items: center;
			gap: var(--space-slim);
			padding: var(--space-small) var(--space-base) 0;
			text-align: center;
		}

		&__done-title {
			margin: var(--space-smaller) 0 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
		}

		&__done-line {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: 1.6;
		}

		&__band--short {
			justify-self: stretch;
			margin-top: var(--space-smaller);
			text-align: left;
		}
	}
</style>
