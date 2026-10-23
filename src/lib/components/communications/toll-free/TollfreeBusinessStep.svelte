<script lang="ts">
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import RadioTile from '$lib/components/ui/RadioTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { countryName } from '$lib/components/communications/paperwork/paperwork-ui';
	import type { TollfreeAddress } from '$lib/communications/sms-tollfree';
	import type { TollfreeDraft } from './tollfree-draft.svelte';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 1 of the toll-free check (`concept.pen` board `SCpaW`, "Business details"): who uses the number, the
	// business, the person in charge and the address, filled in from the texting registration.
	let {
		draft,
		registrationAddress,
		errors,
		continuing,
		backHref,
		onContinue
	}: {
		draft: TollfreeDraft;
		registrationAddress: Partial<TollfreeAddress> | null;
		/** What to correct, by answer path, after a send was refused. */
		errors: Record<string, string>;
		continuing: boolean;
		backHref: string;
		onContinue: () => void;
	} = $props();

	const business = $derived(draft.business);
	const soleTrader = $derived(business.business_type === 'sole_proprietorship');
	const address = $derived(business.business_address);
	const sameAsRegistration = $derived(
		Boolean(registrationAddress?.line1) &&
			(['line1', 'line2', 'city', 'region', 'postal_code', 'country_code'] as const).every(
				(part) =>
					(address[part] ?? '').trim().toLowerCase() ===
					(registrationAddress?.[part] ?? '').trim().toLowerCase()
			)
	);
	let editingAddress = $state(false);
	const showAddressFields = $derived(editingAddress || !sameAsRegistration);

	function setOwner(sole: boolean) {
		if (sole === soleTrader) return;
		// "A business" keeps no finer kind on this form; Twilio files every non-sole-trader the same way.
		business.business_type = sole ? 'sole_proprietorship' : 'other';
		draft.changed();
	}

	const input = (event: Event) => (event.currentTarget as HTMLInputElement).value;
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Business details"
	hint="Filled in from your texting registration. Check each one matches your documents."
	icon={buildingIcon}
	tone="conversation"
>
	<div class="tollfree-business">
		<fieldset class="tollfree-business__owner">
			<legend id="tollfree-owner">Who will use this toll-free number?</legend>
			<div class="tollfree-business__tiles" role="radiogroup" aria-labelledby="tollfree-owner">
				<RadioTile
					name="tollfree-owner"
					value="business"
					checked={!soleTrader}
					icon={buildingIcon}
					tone="conversation"
					title="A business"
					description="A company or sole trader with a registration number"
					onselect={() => setOwner(false)}
				/>
				<RadioTile
					name="tollfree-owner"
					value="individual"
					checked={soleTrader}
					icon={userIcon}
					tone="conversation"
					title="Just me"
					description="A person, checked with a passport or ID card"
					onselect={() => setOwner(true)}
				/>
			</div>
		</fieldset>

		<section class="tollfree-business__group" aria-labelledby="tollfree-business">
			<header>
				<h3 id="tollfree-business">{soleTrader ? 'Your business' : 'Business'}</h3>
				<p>Filled from your texting registration. Change anything that is out of date.</p>
			</header>
			<div class="tollfree-business__fields">
				<Input
					id="tollfree-name"
					label={soleTrader ? 'Business or trading name' : 'Legal business name'}
					required
					bind:value={business.legal_business_name}
					errorMessage={errors['legal_business_name']}
					oninput={() => draft.changed()}
				/>
				<CountryPicker
					id="tollfree-registered"
					label="Where it is registered"
					value={business.business_registration_country ?? address.country_code}
					onchange={(code) => {
						business.business_registration_country = code;
						draft.changed();
					}}
				/>
				<Input
					id="tollfree-registration"
					label={soleTrader ? 'Registration number (optional)' : 'Registration number'}
					required={!soleTrader}
					value={business.business_registration_id ?? ''}
					errorMessage={errors['business_registration_id']}
					oninput={(event: Event) => {
						business.business_registration_id = input(event);
						draft.changed();
					}}
				/>
				<Input
					id="tollfree-website"
					label="Website"
					type="url"
					required
					placeholder="https://"
					bind:value={business.website_url}
					errorMessage={errors['website_url']}
					oninput={() => draft.changed()}
				/>
			</div>
		</section>

		<section class="tollfree-business__group" aria-labelledby="tollfree-person">
			<header>
				<h3 id="tollfree-person">Person in charge</h3>
				<p>A real person the phone company can contact about these texts.</p>
			</header>
			<div class="tollfree-business__fields">
				<Input
					id="tollfree-first"
					label="First name"
					required
					autocomplete="given-name"
					bind:value={business.authorized_representative.first_name}
					errorMessage={errors['authorized_representative.first_name']}
					oninput={() => draft.changed()}
				/>
				<Input
					id="tollfree-last"
					label="Last name"
					required
					autocomplete="family-name"
					bind:value={business.authorized_representative.last_name}
					errorMessage={errors['authorized_representative.last_name']}
					oninput={() => draft.changed()}
				/>
				<Input
					id="tollfree-email"
					label="Email"
					type="email"
					required
					autocomplete="email"
					bind:value={business.authorized_representative.email}
					errorMessage={errors['authorized_representative.email']}
					oninput={() => draft.changed()}
				/>
				<div class="tollfree-business__phone">
					<Input
						id="tollfree-phone"
						label="Phone"
						type="tel"
						required
						autocomplete="tel"
						placeholder="+1 604 555 0182"
						value={business.authorized_representative.phone_number}
						errorMessage={errors['authorized_representative.phone_number']}
						oninput={(event: Event) => {
							// Twilio wants +16045550182: spaces, dashes and brackets are for reading only.
							business.authorized_representative.phone_number = input(event).replace(
								/[\s().-]/g,
								''
							);
							draft.changed();
						}}
					/>
					{#if !errors['authorized_representative.phone_number']}
						<p>A real business or mobile line, not a number from a texting company.</p>
					{/if}
				</div>
			</div>
		</section>

		<section class="tollfree-business__group" aria-labelledby="tollfree-address">
			<header>
				<h3 id="tollfree-address">Business address</h3>
				<p>The real place where your business operates.</p>
			</header>
			{#if !showAddressFields}
				<div class="tollfree-business__address">
					<IconTile icon={mapPinIcon} tone="client" size={32} />
					<span class="tollfree-business__address-copy">
						<strong>{[address.line1, address.line2].filter(Boolean).join(', ')}</strong>
						<span
							>{[
								address.city,
								[address.region, address.postal_code].filter(Boolean).join(' '),
								countryName(address.country_code)
							]
								.filter(Boolean)
								.join(', ')}</span
						>
					</span>
					<StatusBadge status="success">Same as your registration</StatusBadge>
				</div>
				<button
					type="button"
					class="tollfree-business__link"
					onclick={() => (editingAddress = true)}
				>
					<span aria-hidden="true">{@html plusIcon}</span>
					Use a different address
				</button>
			{:else}
				<div class="tollfree-business__fields">
					<Input
						id="tollfree-street"
						label="Street address"
						required
						autocomplete="address-line1"
						bind:value={address.line1}
						errorMessage={errors['business_address.line1']}
						oninput={() => draft.changed()}
					/>
					<Input
						id="tollfree-street-2"
						label="Unit or suite"
						autocomplete="address-line2"
						value={address.line2 ?? ''}
						oninput={(event: Event) => {
							address.line2 = input(event);
							draft.changed();
						}}
					/>
					<Input
						id="tollfree-city"
						label="City"
						required
						autocomplete="address-level2"
						bind:value={address.city}
						errorMessage={errors['business_address.city']}
						oninput={() => draft.changed()}
					/>
					<Input
						id="tollfree-region"
						label="State, province or region"
						required
						autocomplete="address-level1"
						bind:value={address.region}
						errorMessage={errors['business_address.region']}
						oninput={() => draft.changed()}
					/>
					<Input
						id="tollfree-postal"
						label="Postal code"
						required
						autocomplete="postal-code"
						bind:value={address.postal_code}
						errorMessage={errors['business_address.postal_code']}
						oninput={() => draft.changed()}
					/>
					<CountryPicker
						id="tollfree-address-country"
						label="Country"
						required
						value={address.country_code}
						errorMessage={errors['business_address.country_code']}
						onchange={(code) => {
							address.country_code = code;
							draft.changed();
						}}
					/>
				</div>
				{#if registrationAddress?.line1 && !sameAsRegistration}
					<button
						type="button"
						class="tollfree-business__link"
						onclick={() => {
							Object.assign(address, registrationAddress);
							editingAddress = false;
							draft.changed();
						}}
					>
						<span aria-hidden="true">{@html mapPinIcon}</span>
						Use your registration address
					</button>
				{/if}
			{/if}
		</section>
	</div>

	{#snippet footer()}
		<Button variant="secondary" href={backHref}>
			<span aria-hidden="true">{@html arrowLeftIcon}</span>
			Back
		</Button>
		<span class="tollfree-business__foot">Step 1 of 4 · saved as you type</span>
		<Button loading={continuing} onclick={onContinue}>
			{#if !continuing}<span aria-hidden="true">{@html arrowRightIcon}</span>{/if}
			Continue
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The same groups as New paperwork's Business details (`PaperworkDetailsStep`), one board apart.
	.tollfree-business {
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

		&__fields {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
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

		&__phone {
			display: flex;
			flex-direction: column;
			gap: 6px;
			min-width: 0;

			p {
				line-height: var(--typography--lineHeight-large);
			}
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

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
