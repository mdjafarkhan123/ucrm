<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import RadioTile from '$lib/components/ui/RadioTile.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PaperworkFrame from '$lib/components/communications/paperwork/PaperworkFrame.svelte';
	import { kindName } from '$lib/components/communications/paperwork/paperwork-ui';
	import {
		paperworkKeys,
		startPaperwork,
		type PaperworkRequestError
	} from '$lib/communications/number-paperwork';
	import {
		fetchNumberCountries,
		fetchNumberKinds,
		numberCountriesKey,
		numberKindsKey,
		type NumberType
	} from '$lib/communications/sms-number-shop';
	import { countryDisplayName } from '$lib/settings/country-names';
	import flagIcon from '@tabler/icons/outline/flag.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import mobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import phoneCallIcon from '@tabler/icons/outline/phone-call.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// New paperwork, step 1 (Stage 10 Part 3): the country and kind of number. Add number's "Start paperwork"
	// already knows both, so with `?country&type` the set starts at once and the page moves to its details.
	const queryClient = useQueryClient();
	const NO_PAPERWORK = new Set(['US', 'CA']);
	const KIND_ICONS: Record<NumberType, string> = {
		local: mapPinIcon,
		mobile: mobileIcon,
		national: worldIcon,
		toll_free: phoneCallIcon
	};
	const KIND_HINTS: Record<NumberType, string> = {
		local: 'A number with a city’s area code',
		mobile: 'A mobile number, the kind most people text from',
		national: 'One number for the whole country',
		toll_free: 'Free for customers to call'
	};

	const preset = {
		country: (page.url.searchParams.get('country') ?? '').toUpperCase(),
		type: page.url.searchParams.get('type') as NumberType | null
	};
	const startsAtOnce = /^[A-Z]{2}$/.test(preset.country) && Boolean(preset.type);

	let country = $state(startsAtOnce ? '' : preset.country);
	let numberType = $state<NumberType | null>(null);
	let starting = $state(false);
	let startError = $state('');

	const countriesQuery = createQuery(() => ({
		queryKey: numberCountriesKey,
		queryFn: fetchNumberCountries,
		enabled: !startsAtOnce
	}));
	const kindsQuery = createQuery(() => ({
		queryKey: numberKindsKey(country),
		queryFn: () => fetchNumberKinds(country),
		enabled: Boolean(country) && !startsAtOnce
	}));

	const countryCodes = $derived(
		countriesQuery.data?.countries
			.map((item) => item.country_code)
			.filter((code) => !NO_PAPERWORK.has(code))
	);
	const kinds = $derived(
		(kindsQuery.data?.kinds ?? []).filter(
			(kind) => kind.can_text && kind.needs === 'paperwork_first'
		)
	);

	// A kind picked for one country doesn't carry over to a country without it.
	const pickedType = $derived(
		kinds.some((kind) => kind.number_type === numberType) ? numberType : null
	);

	async function start(code: string, type: NumberType, replace: boolean) {
		starting = true;
		startError = '';
		try {
			const detail = await startPaperwork({
				country_code: code,
				number_type: type,
				end_user_type: 'business'
			});
			queryClient.setQueryData(paperworkKeys.detail(detail.id), detail);
			void queryClient.invalidateQueries({ queryKey: paperworkKeys.list() });
			await goto(
				`${resolve('/(app)/settings/communications/sms/paperwork/[id=uuid]', { id: detail.id })}?step=details`,
				{ replaceState: replace }
			);
		} catch (error) {
			startError = (error as PaperworkRequestError).message;
			starting = false;
		}
	}

	onMount(() => {
		if (startsAtOnce && preset.type) void start(preset.country, preset.type, true);
	});
</script>

<svelte:head><title>New paperwork · Contractor CRM</title></svelte:head>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<PaperworkFrame
	crumb="New paperwork"
	title="New paperwork"
	description="Pick the country and kind of number. Each set covers one of each."
	step={1}
	stepHints={['', 'Who you are', 'What they ask for', 'Last step']}
>
	{#if startsAtOnce}
		{#if startError}
			<ErrorState
				title="Paperwork couldn’t start"
				description={startError}
				retry={() => preset.type && start(preset.country, preset.type, true)}
			/>
		{:else}
			<LoadingSkeleton
				variant="card"
				rows={4}
				label={`Reading what ${countryDisplayName(preset.country)} asks for`}
			/>
		{/if}
	{:else}
		<SetupStepCard
			title="Country and kind"
			hint="Paperwork covers one country and one kind of number."
			icon={flagIcon}
			tone="conversation"
		>
			{#if countriesQuery.isError}
				<ErrorState
					description="The countries couldn’t load. Try again in a minute."
					retry={() => countriesQuery.refetch()}
				/>
			{:else}
				<CountryPicker
					id="paperwork-country"
					label="Country"
					required
					bind:value={country}
					only={countryCodes}
					disabled={countriesQuery.isPending}
					placeholder={countriesQuery.isPending ? 'Loading countries…' : 'Search countries'}
				/>
				<p class="paperwork-new__hint">
					US and Canadian numbers need no paperwork. They need a texting registration instead.
				</p>

				{#if country}
					<div class="paperwork-new__kinds">
						<span class="paperwork-new__label" id="paperwork-kind">Kind of number</span>
						{#if kindsQuery.isPending}
							<LoadingSkeleton variant="text" rows={2} label="Loading the kinds of number" />
						{:else if kindsQuery.isError}
							<ErrorState
								size="small"
								description="The kinds of number couldn’t load."
								retry={() => kindsQuery.refetch()}
							/>
						{:else if kinds.length === 0}
							<Banner type="notice">
								{countryDisplayName(country)} needs no paperwork for its texting numbers. Buy one from
								Add number in Phone &amp; SMS.
							</Banner>
						{:else}
							<div class="paperwork-new__tiles" role="radiogroup" aria-labelledby="paperwork-kind">
								{#each kinds as kind (kind.number_type)}
									<RadioTile
										name="paperwork-kind"
										value={kind.number_type}
										checked={pickedType === kind.number_type}
										icon={KIND_ICONS[kind.number_type]}
										tone="conversation"
										title={kindName(kind.number_type)}
										description={KIND_HINTS[kind.number_type]}
										onselect={() => (numberType = kind.number_type)}
									/>
								{/each}
							</div>
						{/if}
					</div>
				{/if}
				{#if startError}<Banner type="error">{startError}</Banner>{/if}
			{/if}

			{#snippet footer()}
				<Button variant="secondary" href={resolve('/(app)/settings/communications/sms/paperwork')}>
					<span aria-hidden="true">{@html arrowLeftIcon}</span>
					Back
				</Button>
				<span class="paperwork-new__foot">Step 1 of 4</span>
				<Button
					loading={starting}
					disabled={!country || !pickedType}
					onclick={() => pickedType && start(country, pickedType, false)}
				>
					{#if !starting}<span aria-hidden="true">{@html arrowRightIcon}</span>{/if}
					Continue
				</Button>
			{/snippet}
		</SetupStepCard>
	{/if}
</PaperworkFrame>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-new {
		&__hint {
			margin: calc(-1 * var(--space-small)) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__kinds {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__tiles {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-slim);
		}

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
