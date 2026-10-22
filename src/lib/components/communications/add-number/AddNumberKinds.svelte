<script lang="ts">
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		formatMinor,
		numberTypeLabel,
		type NumberKind,
		type NumberType
	} from '$lib/communications/sms-number-shop';
	import { countryInSentence, kindChoices, type KindChoice } from './add-number';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';

	// Step 1 of Add number (`concept.pen` board `qaFQf`): the country, then the kind of number as three tiles. A kind
	// the country can't text from is greyed with the reason, the way GoHighLevel's number search only offers what can
	// text.
	let {
		country = $bindable(),
		numberType = $bindable(),
		countryCodes,
		kinds,
		loading,
		failed,
		retry
	}: {
		country: string;
		numberType: NumberType | null;
		countryCodes: readonly string[] | undefined;
		kinds: NumberKind[] | undefined;
		loading: boolean;
		failed: boolean;
		retry: () => void;
	} = $props();

	let countryName = $derived(countryInSentence(country, countryDisplayName(country)));
	let choices = $derived(kinds ? kindChoices(kinds, countryName) : []);
	let nothingToBuy = $derived(kinds !== undefined && choices.every((choice) => !choice.available));
	// Some kinds can text but Jafar hasn't priced them yet, as opposed to a country with no texting numbers at all.
	let waitingForPrices = $derived(
		nothingToBuy && choices.some((choice) => choice.kind?.can_text)
	);

	const abilities = [
		{ key: 'text', icon: messageIcon, label: 'Text' },
		{ key: 'pictures', icon: photoIcon, label: 'Picture messages' },
		{ key: 'calls', icon: phoneIcon, label: 'Calls' }
	] as const;

	function has(choice: KindChoice, key: (typeof abilities)[number]['key']) {
		if (!choice.kind) return false;
		if (key === 'text') return choice.kind.can_text;
		if (key === 'pictures') return choice.kind.can_send_pictures;
		return choice.kind.can_call;
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="add-number-kinds">
	<header class="add-number-kinds__head">
		<h3>Where are your customers?</h3>
		<p>Pick the country you text. Uplift only shows numbers that can text there.</p>
	</header>

	<div class="add-number-kinds__country">
		<CountryPicker
			id="add-number-country"
			label="Country"
			bind:value={country}
			only={countryCodes}
			disabled={!countryCodes}
		/>
	</div>

	<fieldset class="add-number-kinds__kinds">
		<legend>What kind of number?</legend>
		{#if failed}
			<ErrorState
				title="We couldn’t reach the phone company"
				description="Nothing was bought or charged. This is usually over in a minute."
				{retry}
			/>
		{:else if loading || !kinds}
			<div class="add-number-kinds__grid">
				{#each [0, 1, 2] as slot (slot)}
					<div class="add-number-kinds__skeleton"><LoadingSkeleton variant="card" rows={3} /></div>
				{/each}
			</div>
		{:else}
			<div class="add-number-kinds__grid">
				{#each choices as choice (choice.numberType)}
					{@const chosen = numberType === choice.numberType}
					<label
						class="kind-tile"
						class:kind-tile--chosen={chosen}
						class:kind-tile--off={!choice.available}
					>
						<input
							class="kind-tile__input"
							type="radio"
							name="add-number-kind"
							value={choice.numberType}
							checked={chosen}
							disabled={!choice.available}
							onchange={() => (numberType = choice.numberType)}
						/>
						<span class="kind-tile__top">
							<IconTile
								icon={choice.icon}
								tone={choice.available ? 'conversation' : 'inactive'}
								size={32}
							/>
							<span class="kind-tile__name">{numberTypeLabel(choice.numberType)}</span>
							<span class="kind-tile__radio" aria-hidden="true">
								{#if chosen}{@html checkIcon}{/if}
							</span>
						</span>
						<span class="kind-tile__description">{choice.description}</span>
						<span class="kind-tile__abilities">
							{#each abilities as ability (ability.key)}
								<span
									class="kind-tile__ability"
									class:kind-tile__ability--on={choice.available && has(choice, ability.key)}
									title={ability.label}
									aria-hidden="true">{@html ability.icon}</span
								>
							{/each}
							<span class="kind-tile__sr">
								{abilities
									.filter((ability) => has(choice, ability.key))
									.map((ability) => ability.label)
									.join(', ') || 'Nothing it can do here'}
							</span>
						</span>
						<span class="kind-tile__price">
							{#if choice.available && choice.kind?.monthly_minor != null}
								From <strong
									>{formatMinor(choice.kind.monthly_minor, choice.kind.currency_code)}</strong
								>
								<span class="kind-tile__per">a month</span>
							{:else}
								<span aria-label="No price">—</span>
							{/if}
						</span>
						{#if choice.band}
							<span class="kind-tile__band kind-tile__band--{choice.band.tone}">
								<span aria-hidden="true"
									>{@html choice.band.tone === 'inactive'
										? banIcon
										: choice.band.tone === 'warning'
											? fileTextIcon
											: fileCheckIcon}</span
								>
								{choice.band.text}
							</span>
						{/if}
					</label>
				{/each}
			</div>

			{#if waitingForPrices}
				<Banner type="notice">
					Uplift hasn’t set prices for numbers in {countryName} yet, so there is nothing to buy here
					today. Check back soon, or ask Uplift.
				</Banner>
			{:else if nothingToBuy}
				<Banner type="warning">
					None of the numbers sold in {countryName} can text, so there is nothing to buy here. Calls-only
					numbers are never shown for texting.
				</Banner>
			{/if}
		{/if}
	</fieldset>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.add-number-kinds {
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

		&__country {
			max-width: 360px;
		}

		&__kinds {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			min-width: 0;
			margin: 0;
			padding: 0;
			border: 0;

			legend {
				margin-bottom: var(--space-small);
				padding: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
			}
		}

		&__grid {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-slim);
		}

		&__skeleton {
			min-height: 220px;
		}
	}

	.kind-tile {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		cursor: pointer;
		transition:
			border-color 120ms ease,
			box-shadow 120ms ease;

		&:hover:not(.kind-tile--off) {
			border-color: var(--color-border--interactive--hover);
		}

		&:has(.kind-tile__input:focus-visible) {
			outline: var(--border-thick) solid var(--color-focus);
			outline-offset: var(--space-smallest);
		}

		&--chosen {
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 0.5px var(--color-interactive);
		}

		&--off {
			background: var(--color-surface--background--subtle);
			cursor: not-allowed;
			opacity: 0.8;
		}

		&__input {
			position: absolute;
			opacity: 0;
			pointer-events: none;
		}

		&__top {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__name {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;

			.kind-tile--off & {
				color: var(--color-text--secondary);
			}
		}

		&__radio {
			display: grid;
			place-items: center;
			width: 22px;
			height: 22px;
			box-sizing: border-box;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-text--reverse);

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			.kind-tile--chosen & {
				border-color: var(--color-interactive);
				background: var(--color-interactive);
			}

			.kind-tile--off & {
				border-color: var(--color-border);
				background: var(--color-surface--background);
			}
		}

		&__description {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
		}

		&__abilities {
			display: flex;
			gap: var(--space-smaller);
		}

		&__ability {
			display: grid;
			place-items: center;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-tile-small);
			background: var(--color-surface--background);
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			&--on {
				background: var(--color-conversation--surface);
				color: var(--color-conversation--onSurface);
			}
		}

		&__price {
			margin-top: auto;
			padding-top: var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);

			strong {
				font-weight: 700;
			}
		}

		&__per {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__sr {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&__band {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			line-height: var(--typography--lineHeight-large);

			:global(svg) {
				flex: 0 0 auto;
				width: 14px;
				height: 14px;
				margin-top: 1px;
			}

			&--informative {
				background: var(--color-informative--surface);
				color: var(--color-informative--onSurface);
			}

			&--warning {
				background: var(--color-warning--surface);
				color: var(--color-warning--onSurface);
			}

			&--inactive {
				background: var(--color-surface--background);
				color: var(--color-text--secondary);
			}
		}
	}
</style>
