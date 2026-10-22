<script lang="ts">
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import RadioTile from '$lib/components/ui/RadioTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import type { PaperworkAddress, PaperworkFix } from '$lib/communications/number-paperwork';
	import PaperworkField from './PaperworkField.svelte';
	import { EMPTY_ADDRESS, type PaperworkDraft } from './paperwork-draft.svelte';
	import { countryName } from './paperwork-ui';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// Step 2 of New paperwork (`concept.pen` board `A0URqF`, "Business details"): who owns the numbers, then the
	// questions the country asks, filled in from the texting registration, and the address.
	let {
		draft,
		registrationAddress,
		problems,
		locked,
		continuing,
		onBack,
		onContinue
	}: {
		draft: PaperworkDraft;
		/** The texting registration's address, for "Same as your registration". */
		registrationAddress: PaperworkAddress | null;
		/** What to correct, shown once Continue was pressed or the phone company sent it back. */
		problems: PaperworkFix[];
		/** Who owns the numbers is settled once the phone company has the set. */
		locked: boolean;
		continuing: boolean;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	const form = $derived(draft.detail.form);
	const business = $derived(draft.endUserType === 'business');
	const errors = $derived(
		Object.fromEntries(
			problems.filter((fix) => fix.step === 'details').map((fix) => [fix.target, fix.reason])
		)
	);
	const addressProblem = $derived(errors.address ?? '');
	const sameAsRegistration = $derived(
		Boolean(registrationAddress && draft.address && sameAddress(draft.address, registrationAddress))
	);
	let editingAddress = $state(false);
	const showAddressFields = $derived(editingAddress || !sameAsRegistration);

	function sameAddress(a: PaperworkAddress, b: PaperworkAddress): boolean {
		const parts = [
			'street',
			'street_secondary',
			'city',
			'region',
			'postal_code',
			'country_code'
		] as const;
		return parts.every(
			(part) => (a[part] ?? '').trim().toLowerCase() === (b[part] ?? '').trim().toLowerCase()
		);
	}

	function setAddressPart(part: keyof PaperworkAddress, value: string) {
		draft.setAddress({ ...(draft.address ?? EMPTY_ADDRESS), [part]: value });
	}

	function useRegistrationAddress() {
		if (!registrationAddress) return;
		draft.setAddress({ ...registrationAddress });
		editingAddress = false;
	}

	const groups = $derived(
		business
			? [
					{
						key: 'business',
						title: 'Business',
						hint: 'As it appears on your company registration',
						fields: form.businessFields
					},
					{
						key: 'person',
						title: 'Person in charge',
						hint: 'Someone the phone company can contact about this business',
						fields: form.personFields
					}
				]
			: [
					{
						key: 'person',
						title: 'About you',
						hint: 'As it appears on your passport or ID card',
						fields: form.personFields
					}
				]
	);
	const addressHint = $derived.by(() => {
		const rule = form.addressRule.trim() || `${countryName(form.countryCode)} accepts an address anywhere.`;
		return /po box/i.test(rule) ? rule : `${rule.replace(/\.?$/, '.')} No PO boxes.`;
	});
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title={business ? 'Business details' : 'Your details'}
	hint="Filled in from your texting registration. Check each one matches your documents."
	icon={buildingIcon}
	tone="conversation"
>
	<div class="paperwork-details">
		<fieldset class="paperwork-details__owner">
			<legend id="paperwork-owner">Who will own these numbers?</legend>
			<div class="paperwork-details__tiles" role="radiogroup" aria-labelledby="paperwork-owner">
				<RadioTile
					name="paperwork-owner"
					value="business"
					checked={business}
					icon={buildingIcon}
					tone="conversation"
					title="A business"
					description="A company or sole trader with a registration number"
					disabled={locked && !business}
					onselect={() => draft.setEndUserType('business')}
				/>
				<RadioTile
					name="paperwork-owner"
					value="individual"
					checked={!business}
					icon={userIcon}
					tone="conversation"
					title="Just me"
					description="A person, checked with a passport or ID card"
					disabled={locked && business}
					onselect={() => draft.setEndUserType('individual')}
				/>
			</div>
		</fieldset>

		{#each groups as group (group.key)}
			{#if group.fields.length}
				<section class="paperwork-details__group" aria-labelledby={`paperwork-${group.key}`}>
					<header>
						<h3 id={`paperwork-${group.key}`}>{group.title}</h3>
						<p>{group.hint}</p>
					</header>
					<div class="paperwork-details__fields">
						{#each group.fields as field (field.name)}
							<PaperworkField
								{field}
								idPrefix="paperwork"
								value={draft.answers[field.name] ?? ''}
								error={errors[field.name]}
								onchange={(value) => draft.setAnswer(field.name, value)}
							/>
						{/each}
					</div>
				</section>
			{/if}
		{/each}

		{#if form.needsAddress}
			<section class="paperwork-details__group" aria-labelledby="paperwork-address">
				<header>
					<h3 id="paperwork-address">{business ? 'Business address' : 'Home address'}</h3>
					<p>{addressHint}</p>
				</header>

				{#if !showAddressFields && draft.address}
					<div class="paperwork-details__address">
						<IconTile icon={mapPinIcon} tone="client" size={32} />
						<span class="paperwork-details__address-copy">
							<strong
								>{[draft.address.street, draft.address.street_secondary]
									.filter(Boolean)
									.join(', ')}</strong
							>
							<span
								>{[
									draft.address.city,
									[draft.address.region, draft.address.postal_code].filter(Boolean).join(' '),
									draft.address.country_code ? countryName(draft.address.country_code) : ''
								]
									.filter(Boolean)
									.join(', ')}</span
							>
						</span>
						<StatusBadge status="success">Same as your registration</StatusBadge>
					</div>
					<button
						type="button"
						class="paperwork-details__link"
						onclick={() => (editingAddress = true)}
					>
						<span aria-hidden="true">{@html plusIcon}</span>
						Use a different address
					</button>
				{:else}
					{@const address = draft.address ?? EMPTY_ADDRESS}
					<div class="paperwork-details__fields">
						<Input
							id="paperwork-street"
							label="Street address"
							required
							value={address.street}
							autocomplete="address-line1"
							oninput={(event: Event) =>
								setAddressPart('street', (event.currentTarget as HTMLInputElement).value)}
						/>
						<Input
							id="paperwork-street-2"
							label="Unit or suite"
							value={address.street_secondary}
							autocomplete="address-line2"
							oninput={(event: Event) =>
								setAddressPart('street_secondary', (event.currentTarget as HTMLInputElement).value)}
						/>
						<Input
							id="paperwork-city"
							label="City"
							required
							value={address.city}
							autocomplete="address-level2"
							oninput={(event: Event) =>
								setAddressPart('city', (event.currentTarget as HTMLInputElement).value)}
						/>
						<Input
							id="paperwork-region"
							label="State, province or region"
							required
							value={address.region}
							autocomplete="address-level1"
							oninput={(event: Event) =>
								setAddressPart('region', (event.currentTarget as HTMLInputElement).value)}
						/>
						<Input
							id="paperwork-postal"
							label="Postal code"
							required
							value={address.postal_code}
							autocomplete="postal-code"
							oninput={(event: Event) =>
								setAddressPart('postal_code', (event.currentTarget as HTMLInputElement).value)}
						/>
						<CountryPicker
							id="paperwork-address-country"
							label="Country"
							required
							value={address.country_code}
							onchange={(code) => setAddressPart('country_code', code)}
						/>
					</div>
					{#if registrationAddress && !sameAsRegistration}
						<button type="button" class="paperwork-details__link" onclick={useRegistrationAddress}>
							<span aria-hidden="true">{@html mapPinIcon}</span>
							Use your registration address
						</button>
					{/if}
				{/if}
				{#if addressProblem}
					<p class="paperwork-details__error" role="alert">
						<span aria-hidden="true">{@html alertIcon}</span>{addressProblem}
					</p>
				{/if}
			</section>
		{/if}
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span aria-hidden="true">{@html arrowLeftIcon}</span>
			Back
		</Button>
		<span class="paperwork-details__foot">Step 2 of 4 · saved as you type</span>
		<Button loading={continuing} onclick={onContinue}>
			{#if !continuing}<span aria-hidden="true">{@html arrowRightIcon}</span>{/if}
			Continue
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-details {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		&__owner {
			margin: 0;
			padding: 0;
			border: 0;

			legend {
				margin-bottom: var(--space-slim);
				padding: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__tiles {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-slim);
		}

		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding-top: var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);

			header {
				display: grid;
				gap: 2px;
			}

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__fields {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__address {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px var(--space-base);
			border: var(--border-base) solid var(--color-interactive);
			border-radius: var(--radius-base);
			box-shadow: inset 0 0 0 0.5px var(--color-interactive);
			background: var(--color-surface);
		}

		&__address-copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__link {
			display: inline-flex;
			align-self: flex-start;
			align-items: center;
			gap: 6px;
			padding: var(--space-smaller) var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-interactive);
			font: inherit;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:active {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-smaller);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
