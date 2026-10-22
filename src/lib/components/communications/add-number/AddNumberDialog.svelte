<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import AddNumberKinds from './AddNumberKinds.svelte';
	import AddNumberList from './AddNumberList.svelte';
	import AddNumberBill from './AddNumberBill.svelte';
	import AddNumberBought from './AddNumberBought.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		buyNumber,
		fetchNumberCountries,
		fetchNumberKinds,
		fetchShopNumbers,
		formatMinor,
		formatPhone,
		numberCountriesKey,
		numberKindsKey,
		numberTypeLabel,
		ProviderUnavailableError,
		shopNumbersKey,
		type NumberOrder,
		type NumberType,
		type ShopNumber
	} from '$lib/communications/sms-number-shop';
	import { countryInSentence, kindChoices, registersAfter } from './add-number';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import shoppingCartIcon from '@tabler/icons/outline/shopping-cart.svg?raw';
	import filePlusIcon from '@tabler/icons/outline/file-plus.svg?raw';

	// Add number (`concept.pen` board `qaFQf`, Approved B, Jafar 2026-10-22): GoHighLevel's Add Number in three steps —
	// country and kind, pick a number, check and buy. Uplift buys it in the business's own Twilio subaccount; a repeat
	// press or a dropped connection continues the same order, so nobody is charged twice.
	let {
		open,
		onClose,
		onRegister
	}: {
		open: boolean;
		onClose: () => void;
		/** Opens the business registration that US and Canadian numbers need before they can text. */
		onRegister?: () => void;
	} = $props();

	const queryClient = useQueryClient();

	// Starts on the business's own country (or the US) until the business picks another.
	let pickedCountry = $state<string | null>(null);
	let numberType = $state<NumberType | null>(null);
	let step = $state<1 | 2 | 3>(1);
	let contains = $state('');
	let searchDigits = $state('');
	let mms = $state(false);
	let voice = $state(false);
	let chosen = $state<ShopNumber | null>(null);
	let buying = $state(false);
	let checking = $state(false);
	let refusal = $state<{ code: string | null; message: string } | null>(null);
	let bought = $state<NumberOrder | null>(null);
	// One key per number being bought: a repeat press or a check after a dropped connection reuses it.
	let orderKey = $state<{ phone: string; key: string } | null>(null);

	$effect(() => {
		const value = contains.trim();
		const handle = setTimeout(() => (searchDigits = value), 300);
		return () => clearTimeout(handle);
	});

	const countriesQuery = createQuery(() => ({
		queryKey: numberCountriesKey,
		queryFn: fetchNumberCountries,
		staleTime: 10 * 60_000,
		enabled: open
	}));
	let country = $derived(pickedCountry ?? countriesQuery.data?.home_country ?? 'US');
	const kindsQuery = createQuery(() => ({
		queryKey: numberKindsKey(country),
		queryFn: () => fetchNumberKinds(country),
		staleTime: 60_000,
		// Wait for the business's own country before asking, so the first answer is the one shown.
		enabled: open && (pickedCountry !== null || !countriesQuery.isPending)
	}));
	let search = $derived({
		country,
		type: numberType ?? 'local',
		contains: searchDigits,
		mms,
		voice
	});
	const numbersQuery = createQuery(() => ({
		queryKey: shopNumbersKey(search),
		queryFn: () => fetchShopNumbers(search),
		staleTime: 30_000,
		enabled: open && step >= 2 && numberType !== null
	}));

	let countryCodes = $derived(countriesQuery.data?.countries.map((entry) => entry.country_code));
	let countryName = $derived(countryDisplayName(country));
	let kinds = $derived(kindsQuery.data?.kinds);
	let choices = $derived(kinds ? kindChoices(kinds, countryInSentence(country, countryName)) : []);
	// A kind that can't be bought here never stays chosen; the first one that can is picked for the business.
	let pickedType = $derived(
		choices.find((choice) => choice.numberType === numberType && choice.available)
			? numberType
			: (choices.find((choice) => choice.available)?.numberType ?? null)
	);
	let kind = $derived(kinds?.find((entry) => entry.number_type === pickedType));
	let currency = $derived(kind?.currency_code ?? kindsQuery.data?.currency_code ?? 'USD');
	let balance = $derived(kindsQuery.data?.balance_minor ?? 0);
	let lowestPrice = $derived(
		choices
			.filter((choice) => choice.available && choice.kind?.monthly_minor != null)
			.map((choice) => choice.kind!.monthly_minor!)
			.sort((a, b) => a - b)[0]
	);
	let paperworkFirst = $derived(kind?.needs === 'paperwork_first');
	let today = $derived((kind?.monthly_minor ?? 0) + (kind?.setup_minor ?? 0));

	function pickType(next: NumberType | null) {
		numberType = next;
	}

	function goTo(next: 1 | 2 | 3) {
		if (next === 2 && pickedType) numberType = pickedType;
		refusal = null;
		step = next;
	}

	function pickAnother() {
		refusal = null;
		chosen = null;
		orderKey = null;
		step = 2;
		void queryClient.invalidateQueries({ queryKey: shopNumbersKey(search) });
	}

	function keyFor(phone: string): string {
		if (orderKey?.phone === phone) return orderKey.key;
		orderKey = { phone, key: crypto.randomUUID() };
		return orderKey.key;
	}

	const CHECK_EVERY_MS = 5_000;
	const CHECK_FOR_MS = 3 * 60_000;

	async function buy() {
		if (!chosen || !pickedType || buying) return;
		buying = true;
		refusal = null;
		const startedAt = Date.now();
		const body = {
			idempotency_key: keyFor(chosen.phone_number),
			phone_number: chosen.phone_number,
			country_code: country,
			number_type: pickedType
		};
		try {
			for (;;) {
				const result = await buyNumber(body);
				if (result.kind === 'done') {
					checking = false;
					if (result.order.state === 'failed') {
						refusal = {
							code: result.order.failure_code,
							message: result.order.failure_message ?? 'The number could not be bought.'
						};
						orderKey = null;
					} else {
						bought = result.order;
						await queryClient.invalidateQueries({
							queryKey: ['settings', 'communications', 'sms']
						});
					}
					return;
				}
				if (result.kind === 'refused') {
					checking = false;
					refusal = { code: result.code, message: result.message };
					if (result.code !== 'provider_unavailable') orderKey = null;
					return;
				}
				checking = true;
				if (Date.now() - startedAt > CHECK_FOR_MS) {
					checking = false;
					refusal = {
						code: 'still_checking',
						message:
							'The phone company still hasn’t answered. Your money is held, not charged. Press Buy again in a few minutes to check; you will never be charged twice.'
					};
					return;
				}
				await new Promise((resolve) => setTimeout(resolve, CHECK_EVERY_MS));
			}
		} finally {
			buying = false;
		}
	}

	type RailStep = { title: string; detail: string; state: 'done' | 'current' | 'next' };
	let rail = $derived<RailStep[]>([
		{
			title: 'Where and what kind',
			detail:
				step > 1 || bought
					? `${countryName} · ${pickedType ? numberTypeLabel(pickedType) : ''}`
					: 'You are here',
			state: step > 1 || bought ? 'done' : 'current'
		},
		{
			title: 'Pick your number',
			detail:
				(step > 2 || bought) && chosen
					? formatPhone(chosen.phone_number)
					: step === 2
						? 'You are here'
						: 'Next',
			state: step > 2 || bought ? 'done' : step === 2 ? 'current' : 'next'
		},
		{
			title: 'Check and buy',
			detail: bought
				? `Bought · ${formatMinor(bought.charge_minor, bought.currency_code)} charged`
				: step === 3
					? 'You are here'
					: 'Next',
			state: bought ? 'done' : step === 3 ? 'current' : 'next'
		}
	]);

	function nextChargeDate(): string {
		const date = new Date();
		date.setMonth(date.getMonth() + 1);
		return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
	}

	let canContinue = $derived(
		step === 1 ? Boolean(pickedType) && !kindsQuery.isPending : step === 2 ? Boolean(chosen) : false
	);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title="Add number"
	subtitle="A new number for texting your customers"
	size="large"
	icon={phoneIcon}
	iconTone="conversation"
	flush
	closeDisabled={buying}
	{onClose}
>
	<div class="add-number">
		<aside class="add-number__rail" aria-label="Steps">
			<p class="add-number__rail-title">3 steps</p>
			<ol class="add-number__steps">
				{#each rail as item, index (item.title)}
					<li
						class="add-number__step add-number__step--{item.state}"
						aria-current={item.state === 'current' ? 'step' : undefined}
					>
						<span class="add-number__step-mark" aria-hidden="true">
							{#if item.state === 'done'}{@html checkIcon}{:else}{index + 1}{/if}
						</span>
						<span class="add-number__step-copy">
							<strong>{item.title}</strong>
							<span>{item.detail}</span>
						</span>
					</li>
				{/each}
			</ol>
			<div class="add-number__price">
				<p class="add-number__price-label">Monthly price</p>
				{#if bought}
					<p class="add-number__price-value">
						{formatMinor(bought.monthly_minor, bought.currency_code)} <span>a month</span>
					</p>
					<p class="add-number__price-note">Next charge on {nextChargeDate()}.</p>
				{:else if step === 1}
					{#if lowestPrice !== undefined}
						<p class="add-number__price-value">
							From {formatMinor(lowestPrice, currency)} <span>a month</span>
						</p>
						<p class="add-number__price-note">
							{#if kind?.setup_minor}
								Plus a {formatMinor(kind.setup_minor, currency)} one-time setup charge.
							{:else}
								Pick a number to see its exact price.
							{/if}
						</p>
					{:else}
						<p class="add-number__price-value">—</p>
						<p class="add-number__price-note">
							{kinds ? 'Nothing to buy for texting here yet.' : 'Pick a country.'}
						</p>
					{/if}
				{:else if kind?.monthly_minor != null}
					<p class="add-number__price-value">
						{formatMinor(kind.monthly_minor, currency)} <span>a month</span>
					</p>
					<p class="add-number__price-note">
						{#if kind.setup_minor}
							Plus a {formatMinor(kind.setup_minor, currency)} one-time setup charge.
						{:else}
							No setup charge. Paid from your texting balance.
						{/if}
					</p>
				{/if}
			</div>
		</aside>

		<div class="add-number__pane">
			{#if bought}
				<AddNumberBought order={bought} />
			{:else if step === 1}
				<AddNumberKinds
					bind:country={() => country, (next) => (pickedCountry = next)}
					bind:numberType={() => pickedType, pickType}
					{countryCodes}
					{kinds}
					loading={kindsQuery.isPending}
					failed={kindsQuery.isError}
					retry={() => kindsQuery.refetch()}
				/>
			{:else if step === 2 && pickedType && kind}
				<AddNumberList
					bind:contains
					bind:mms
					bind:voice
					bind:chosen
					numberType={pickedType}
					numbers={numbersQuery.data}
					loading={numbersQuery.isPending || searchDigits !== contains.trim()}
					failed={numbersQuery.isError}
					retry={() => numbersQuery.refetch()}
					monthlyMinor={kind.monthly_minor ?? 0}
					currencyCode={currency}
				/>
			{:else if step === 3 && chosen && kind}
				<AddNumberBill
					countryCode={country}
					number={chosen}
					{kind}
					balanceMinor={balance}
					{checking}
					{refusal}
					onPickAnother={pickAnother}
				/>
			{/if}
		</div>
	</div>

	{#snippet footer()}
		<span class="add-number__progress">{bought ? 'All done' : `Step ${step} of 3`}</span>
		<div class="add-number__actions">
			{#if bought}
				<Button variant="secondary" onclick={onClose}>Done</Button>
				{#if registersAfter(bought.country_code) && onRegister}
					<Button onclick={onRegister}>
						<span aria-hidden="true">{@html arrowRightIcon}</span>
						{bought.number_type === 'toll_free'
							? 'Start the toll-free check'
							: 'Register your business'}
					</Button>
				{/if}
			{:else}
				{#if step === 1}
					<Button variant="secondary" onclick={onClose}>Cancel</Button>
				{:else}
					<Button variant="secondary" disabled={buying} onclick={() => goTo(step === 3 ? 2 : 1)}>
						<span aria-hidden="true">{@html arrowLeftIcon}</span>
						Back
					</Button>
				{/if}
				{#if step < 3}
					<Button disabled={!canContinue} onclick={() => goTo(step === 1 ? 2 : 3)}>
						<span aria-hidden="true">{@html arrowRightIcon}</span>
						Continue
					</Button>
				{:else if paperworkFirst}
					<Button
						href={`/settings/communications/sms/paperwork/new?country=${country}&type=${pickedType}`}
					>
						<span aria-hidden="true">{@html filePlusIcon}</span>
						Start paperwork
					</Button>
				{:else}
					<Button loading={buying} disabled={balance < today} onclick={buy}>
						{#if !buying}<span aria-hidden="true">{@html shoppingCartIcon}</span>{/if}
						{checking ? 'Checking…' : `Buy for ${formatMinor(today, currency)}`}
					</Button>
				{/if}
			{/if}
		</div>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.add-number {
		display: flex;
		min-height: 480px;

		&__rail {
			display: flex;
			flex: 0 0 260px;
			flex-direction: column;
			gap: calc(var(--space-smaller) + var(--space-smallest));
			box-sizing: border-box;
			padding: var(--space-base);
			border-right: var(--border-base) solid var(--color-conversation--surface-edge);
			background: var(--color-conversation--surface);
		}

		&__rail-title {
			margin: 0 0 var(--space-smaller);
			color: var(--color-conversation--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__steps {
			display: flex;
			flex-direction: column;
			gap: calc(var(--space-smaller) + var(--space-smallest));
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__step {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: calc(var(--space-small) + var(--space-smallest));
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-tile-large);

			&--current {
				border-color: var(--color-conversation--surface-edge);
				background: var(--color-surface);
			}
		}

		&__step-mark {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 28px;
			height: 28px;
			box-sizing: border-box;
			border: var(--border-base) solid var(--color-conversation--surface-edge);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-conversation--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			.add-number__step--current & {
				border: 1.5px solid var(--color-conversation);
			}

			.add-number__step--done & {
				border-color: var(--color-conversation);
				background: var(--color-conversation);
				color: var(--color-text--reverse);
			}
		}

		&__step-copy {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-conversation--onSurface);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__price {
			margin-top: auto;
			padding: calc(var(--space-slim) + var(--space-smallest));
			border: var(--border-base) solid var(--color-conversation--surface-edge);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface);

			p {
				margin: 0;
			}

			p + p {
				margin-top: var(--space-small);
			}
		}

		&__price-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__price-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 400;
			}
		}

		&__price-note {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			line-height: var(--typography--lineHeight-large);
		}

		&__pane {
			flex: 1 1 auto;
			min-width: 0;
			padding: var(--space-large);
			overflow-y: auto;
		}

		&__progress {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
		}
	}
</style>
