<script lang="ts">
	import { City, Country, type ICity } from 'country-state-city';
	import { Combobox } from 'bits-ui';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	let {
		value = $bindable(''),
		id,
		invalid = false,
		errorMessage = '',
		required = false
	}: {
		value?: string;
		id: string;
		invalid?: boolean;
		errorMessage?: string;
		required?: boolean;
	} = $props();

	const countries = Country.getAllCountries().sort((a, b) => a.name.localeCompare(b.name));
	const countryItems = countries.map((country) => ({
		value: country.isoCode,
		label: country.name
	}));
	let countryCode = $state('');
	let countryQuery = $state('');
	let cityQuery = $state('');
	let selectedCityValue = $state('');
	let countryOpen = $state(false);
	let cityOpen = $state(false);

	let selectedCountry = $derived(countries.find((country) => country.isoCode === countryCode));
	let countryInputValue = $derived(countryOpen ? countryQuery : (selectedCountry?.name ?? ''));
	let normalizedCountryQuery = $derived(
		countryQuery === selectedCountry?.name ? '' : countryQuery.trim().toLowerCase()
	);
	let countryResults = $derived(
		countries
			.filter(
				(country) =>
					country.name.toLowerCase().includes(normalizedCountryQuery) ||
					country.isoCode.toLowerCase().includes(normalizedCountryQuery)
			)
			.slice(0, 80)
	);
	let cities = $derived(
		selectedCountry ? (City.getCitiesOfCountry(selectedCountry.isoCode) ?? []) : []
	);
	let cityItems = $derived(cities.map((city) => ({ value: cityValue(city), label: city.name })));
	let selectedCity = $derived(cities.find((city) => cityValue(city) === selectedCityValue));
	let cityInputValue = $derived(cityOpen ? cityQuery : (selectedCity?.name ?? cityQuery));
	let normalizedCityQuery = $derived(
		cityQuery === selectedCity?.name ? '' : cityQuery.trim().toLowerCase()
	);
	let cityResults = $derived(
		cities
			.filter((city) => cityLabel(city).toLowerCase().includes(normalizedCityQuery))
			.sort((a, b) => cityLabel(a).localeCompare(cityLabel(b)))
			.slice(0, 80)
	);
	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);

	function cityValue(city: ICity) {
		return `${city.name}|${city.stateCode}|${city.latitude}|${city.longitude}`;
	}

	function cityLabel(city: ICity) {
		return city.stateCode ? `${city.name}, ${city.stateCode}` : city.name;
	}

	function focusCountry(input: HTMLInputElement) {
		countryQuery = selectedCountry?.name ?? '';
		countryOpen = true;
		input.select();
	}

	function focusCity(input: HTMLInputElement) {
		if (!selectedCountry) return;
		cityQuery = selectedCity?.name ?? '';
		cityOpen = true;
		input.select();
	}

	function chooseCountry(code: string) {
		countryCode = code;
		const country = countries.find((item) => item.isoCode === code);
		countryQuery = country?.name ?? '';
		selectedCityValue = '';
		cityQuery = '';
		value = country?.name ?? '';
		countryOpen = false;
		cityOpen = false;
	}

	function chooseCity(nextValue: string) {
		const city = cities.find((item) => cityValue(item) === nextValue);
		if (!city || !selectedCountry) return;
		selectedCityValue = nextValue;
		cityQuery = city.name;
		value = `${city.name}, ${selectedCountry.name}`;
		cityOpen = false;
	}

	function hydrateInitialValue() {
		if (!value || countryCode) return;
		const parts = value.split(',').map((part) => part.trim());
		const country = countries.find(
			(item) =>
				item.name.toLowerCase() === parts.at(-1)?.toLowerCase() ||
				item.isoCode.toLowerCase() === parts.at(-1)?.toLowerCase()
		);
		if (!country) return;
		countryCode = country.isoCode;
		countryQuery = country.name;
		const initialCityName = parts.length > 1 ? parts.slice(0, -1).join(', ') : '';
		const initialCity = (City.getCitiesOfCountry(country.isoCode) ?? []).find(
			(city) => city.name.toLowerCase() === initialCityName.toLowerCase()
		);
		selectedCityValue = initialCity ? cityValue(initialCity) : '';
		cityQuery = initialCityName;
	}

	hydrateInitialValue();
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="location-picker" class:location-picker--invalid={invalid}>
	<div class="location-picker__fields">
		<div class="location-picker__field">
			<label for={`${id}-country`}
				>Country{#if required}
					<span aria-hidden="true">*</span>{/if}</label
			>
			<Combobox.Root
				type="single"
				bind:value={countryCode}
				bind:open={countryOpen}
				inputValue={countryInputValue}
				items={countryItems}
				onValueChange={chooseCountry}
			>
				<div class="location-picker__control">
					<span class="location-picker__search" aria-hidden="true">{@html searchIcon}</span>
					<Combobox.Input
						id={`${id}-country`}
						placeholder="Search by country or code"
						autocomplete="country-name"
						aria-describedby={describedBy}
						aria-invalid={invalid}
						onfocus={(event) => focusCountry(event.currentTarget)}
						onclick={() => (countryOpen = true)}
						oninput={(event) => {
							countryQuery = event.currentTarget.value;
							countryOpen = true;
						}}
					/>
					<Combobox.Trigger class="location-picker__trigger" aria-label="Show countries">
						<span aria-hidden="true">{@html chevronDownIcon}</span>
					</Combobox.Trigger>
				</div>
				<Combobox.Portal>
					<Combobox.Content
						class="location-picker__menu"
						data-elevation="elevated"
						align="start"
						sideOffset={4}
						collisionPadding={8}
					>
						<Combobox.Viewport class="location-picker__viewport">
							{#each countryResults as country (country.isoCode)}
								<Combobox.Item
									value={country.isoCode}
									label={country.name}
									class="location-picker__option"
								>
									<span class="location-picker__country-code" aria-hidden="true"
										>{country.isoCode}</span
									>
									<span class="location-picker__option-copy"><strong>{country.name}</strong></span>
									{#if countryCode === country.isoCode}<span
											class="location-picker__check"
											aria-hidden="true">{@html checkIcon}</span
										>{/if}
								</Combobox.Item>
							{:else}<div class="location-picker__empty">
									No countries match “{countryQuery}”.
								</div>{/each}
						</Combobox.Viewport>
					</Combobox.Content>
				</Combobox.Portal>
			</Combobox.Root>
		</div>

		<div class="location-picker__field">
			<label for={`${id}-city`}
				>City{#if required}
					<span aria-hidden="true">*</span>{/if}</label
			>
			<Combobox.Root
				type="single"
				bind:value={selectedCityValue}
				bind:open={cityOpen}
				inputValue={cityInputValue}
				items={cityItems}
				disabled={!selectedCountry}
				onValueChange={chooseCity}
			>
				<div class="location-picker__control">
					<span class="location-picker__search" aria-hidden="true">{@html searchIcon}</span>
					<Combobox.Input
						id={`${id}-city`}
						placeholder={selectedCountry ? 'Search cities' : 'Select a country first'}
						autocomplete="address-level2"
						aria-describedby={describedBy}
						aria-invalid={invalid}
						onfocus={(event) => focusCity(event.currentTarget)}
						onclick={() => (cityOpen = true)}
						oninput={(event) => {
							cityQuery = event.currentTarget.value;
							cityOpen = true;
						}}
					/>
					<Combobox.Trigger
						class="location-picker__trigger"
						aria-label="Show cities"
						disabled={!selectedCountry}
					>
						<span aria-hidden="true">{@html chevronDownIcon}</span>
					</Combobox.Trigger>
				</div>
				<Combobox.Portal>
					<Combobox.Content
						class="location-picker__menu"
						data-elevation="elevated"
						align="start"
						sideOffset={4}
						collisionPadding={8}
					>
						<Combobox.Viewport class="location-picker__viewport">
							{#each cityResults as city (cityValue(city))}
								<Combobox.Item
									value={cityValue(city)}
									label={city.name}
									class="location-picker__option"
								>
									<span class="location-picker__option-copy"
										><strong>{city.name}</strong>{#if city.stateCode}<small>{city.stateCode}</small
											>{/if}</span
									>
									{#if selectedCityValue === cityValue(city)}<span
											class="location-picker__check"
											aria-hidden="true">{@html checkIcon}</span
										>{/if}
								</Combobox.Item>
							{:else}<div class="location-picker__empty">No cities match “{cityQuery}”.</div>{/each}
						</Combobox.Viewport>
					</Combobox.Content>
				</Combobox.Portal>
			</Combobox.Root>
		</div>
	</div>
	{#if errorMessage}<p class="location-picker__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.location-picker {
		width: 100%;
	}
	.location-picker__fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.location-picker__field {
		min-width: 0;
	}
	.location-picker__field > label {
		display: block;
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.location-picker__field > label span {
		color: var(--color-critical);
	}
	.location-picker__control {
		position: relative;
		display: flex;
		min-height: var(--space-largest);
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.location-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}
	.location-picker--invalid .location-picker__control {
		border-color: var(--color-critical);
	}
	.location-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: calc(var(--space-largest) - (var(--border-base) * 2));
		padding: var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
	}
	.location-picker__control :global(input:disabled) {
		color: var(--color-disabled);
		cursor: not-allowed;
		-webkit-text-fill-color: var(--color-disabled);
		opacity: 1;
	}
	.location-picker__control:has(:global(input:disabled)) {
		border-color: var(--color-border);
		background: var(--color-disabled--secondary);
	}
	.location-picker__search {
		position: absolute;
		left: var(--space-base);
		display: grid;
		width: 16px;
		height: 16px;
		place-items: center;
		color: var(--color-icon--secondary);
		pointer-events: none;
	}
	.location-picker__control:has(:global(input:disabled)) .location-picker__search {
		color: var(--color-disabled);
	}
	:global(.location-picker__trigger) {
		position: absolute;
		right: 0;
		display: grid;
		width: var(--space-largest);
		height: 100%;
		place-items: center;
		border: 0;
		border-radius: 0 var(--radius-base) var(--radius-base) 0;
		outline: 0;
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	:global(.location-picker__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}
	:global(.location-picker__trigger:disabled) {
		color: var(--color-disabled);
		cursor: not-allowed;
	}
	:global(.location-picker__trigger[data-state='open']) span {
		transform: rotate(180deg);
	}
	:global(.location-picker__trigger span) {
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		transition: transform var(--timing-quick);
	}
	:global(.location-picker__trigger svg),
	.location-picker__search :global(svg),
	.location-picker__check :global(svg),
	.location-picker__error :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	:global(.location-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(280px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.location-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}
	:global(.location-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}
	:global(.location-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	:global(.location-picker__option[data-selected]) {
		color: var(--color-heading);
	}
	.location-picker__country-code {
		display: grid;
		width: 32px;
		height: 24px;
		flex: 0 0 32px;
		place-items: center;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
	}
	.location-picker__option-copy {
		display: flex;
		min-width: 0;
		flex: 1;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.location-picker__option-copy strong {
		overflow: hidden;
		color: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.location-picker__option-copy small {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.location-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);
	}
	.location-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.location-picker__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 560px) {
		.location-picker__fields {
			grid-template-columns: 1fr;
		}
	}
</style>
