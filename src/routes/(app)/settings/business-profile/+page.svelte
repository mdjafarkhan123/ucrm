<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { Country } from 'country-state-city';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsBusiness,
		settingsBusinessKey,
		saveBusinessProfile,
		isSaveConflict,
		COMMON_CURRENCIES,
		type BusinessProfile,
		type SettingsBusiness
	} from '$lib/settings/api';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsBusinessKey,
		queryFn: fetchSettingsBusiness
	}));

	const TRADES = [
		'General contractor',
		'Plumbing',
		'Electrical',
		'HVAC',
		'Landscaping',
		'Roofing',
		'Painting',
		'Cleaning',
		'Pest control',
		'Handyman',
		'Other'
	];

	const COUNTRIES = Country.getAllCountries()
		.map((country) => ({ value: country.isoCode, label: country.name }))
		.sort((a, b) => a.label.localeCompare(b.label));

	type FormState = {
		name: string;
		trade: string;
		tradeOther: string;
		phone: string;
		website: string;
		description: string;
		address_line1: string;
		address_line2: string;
		city: string;
		region: string;
		postal_code: string;
		country_code: string;
		address_is_public: boolean;
		timezone: string;
		currency_code: string;
	};

	function toForm(profile: BusinessProfile): FormState {
		const knownTrade =
			profile.trade && TRADES.includes(profile.trade)
				? profile.trade
				: profile.trade
					? 'Other'
					: '';
		return {
			name: profile.name,
			trade: knownTrade,
			tradeOther: knownTrade === 'Other' ? (profile.trade ?? '') : '',
			phone: profile.phone ?? '',
			website: profile.website ?? '',
			description: profile.description ?? '',
			address_line1: profile.address_line1 ?? '',
			address_line2: profile.address_line2 ?? '',
			city: profile.city ?? '',
			region: profile.region ?? '',
			postal_code: profile.postal_code ?? '',
			country_code: profile.country_code ?? '',
			address_is_public: profile.address_is_public,
			timezone: profile.timezone,
			currency_code: profile.currency_code
		};
	}

	let form = $state<FormState | null>(null);
	let saved = $state<FormState | null>(null);
	let timezoneConfirmed = $state(false);
	let currencyConfirmed = $state(false);
	let saving = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);
	let layout = $state<RecordFormLayout>();

	// One place the form shows why a save did not land — a plain error, or someone else getting there first.
	const saveError = $derived(
		conflict
			? `${conflict.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version before saving yours.`
			: errorMessage
	);

	$effect(() => {
		const business = query.data;
		if (!business) return;
		untrack(() => {
			if (form) return;
			form = toForm(business.profile);
			saved = toForm(business.profile);
			timezoneConfirmed = business.profile.timezone_confirmed;
			currencyConfirmed = business.profile.currency_confirmed;
		});
	});

	const suggestedTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone;

	function markTimezoneConfirmed() {
		timezoneConfirmed = true;
	}
	function markCurrencyConfirmed() {
		currencyConfirmed = true;
	}

	const dirty = $derived(
		Boolean(form && saved) &&
			(JSON.stringify(form) !== JSON.stringify(saved) ||
				timezoneConfirmed !== (query.data?.profile.timezone_confirmed ?? timezoneConfirmed) ||
				currencyConfirmed !== (query.data?.profile.currency_confirmed ?? currencyConfirmed))
	);

	// Confirmation is only required when the suggested value is actually being changed — matches
	// `save_organization_business_profile`, which rejects an unconfirmed timezone/currency only when it
	// differs from the stored one. Unrelated edits (name, phone, address, ...) must stay saveable.
	const timezoneBlocked = $derived.by(() => {
		if (!form || !saved) return false;
		return form.timezone !== saved.timezone && !timezoneConfirmed;
	});
	const currencyBlocked = $derived.by(() => {
		if (!form || !saved) return false;
		return form.currency_code !== saved.currency_code && !currencyConfirmed;
	});

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		if (!saved || !query.data) return;
		form = { ...saved };
		timezoneConfirmed = query.data.profile.timezone_confirmed;
		currencyConfirmed = query.data.profile.currency_confirmed;
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!form || !query.data) return;
		saving = true;
		errorMessage = '';
		conflict = null;

		const trade = form.trade === 'Other' ? form.tradeOther.trim() : form.trade;
		const result = await saveBusinessProfile({
			expected_revision: query.data.profile.revision,
			name: form.name,
			trade,
			phone: form.phone,
			website: form.website,
			description: form.description,
			address_line1: form.address_line1,
			address_line2: form.address_line2,
			city: form.city,
			region: form.region,
			postal_code: form.postal_code,
			country_code: form.country_code,
			address_is_public: form.address_is_public,
			timezone: form.timezone,
			currency_code: form.currency_code,
			confirm_timezone: timezoneConfirmed,
			confirm_currency: currencyConfirmed
		}).catch((error: Error) => {
			errorMessage = error.message;
			return null;
		});

		saving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			conflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			return;
		}
		saved = { ...form };
		toast.success('Business profile saved.');
		// Patch the revision in place before invalidating: invalidateQueries only refetches queries with
		// active observers, and even then the refetch is not guaranteed to land before the next click. An
		// immediate second save must see this save's revision, not a stale one from before this request.
		queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
			current
				? { ...current, profile: { ...current.profile, revision: result.profile_revision } }
				: current
		);
		await queryClient.invalidateQueries({ queryKey: settingsBusinessKey });
		await queryClient.invalidateQueries({ queryKey: ['settings', 'home'] });
	}
</script>

<svelte:head><title>Business profile · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending || !form}
	<LoadingSkeleton variant="card" rows={4} />
{:else if query.isError}
	<ErrorState description="Business profile could not be loaded." retry={() => query.refetch()} />
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.profile.last_editor}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Business profile' }]}
	/>

	<RecordFormLayout
		title="Business profile"
		icon={buildingIcon}
		bind:this={layout}
		error={saveError}
	>
		{#snippet main()}
			{@const f = form}
			{#if f}
				{#if !canEdit}
					<p class="business-profile__readonly">
						Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
								'a teammate'}.{/if}
					</p>
				{/if}

				<div class="business-profile__columns">
					<div class="business-profile__column">
						<SectionBlock title="Identity" form level={3}>
							<Input
								id="bp-name"
								label="Business name"
								bind:value={f.name}
								required
								disabled={!canEdit}
							/>
							<div class="business-profile__row">
								<Select
									id="bp-trade"
									ariaLabel="Trade"
									placeholder="Trade"
									options={TRADES.map((t) => ({ value: t, label: t }))}
									bind:value={f.trade}
									disabled={!canEdit}
								/>
								{#if f.trade === 'Other'}
									<Input
										id="bp-trade-other"
										label="Describe your trade"
										bind:value={f.tradeOther}
										disabled={!canEdit}
									/>
								{/if}
							</div>
							<div class="business-profile__row">
								<Input
									id="bp-phone"
									label="Main phone"
									type="tel"
									bind:value={f.phone}
									disabled={!canEdit}
								/>
								<Input
									id="bp-website"
									label="Website"
									type="url"
									bind:value={f.website}
									disabled={!canEdit}
								/>
							</div>
							<Textarea
								id="bp-description"
								label="Short description or tagline"
								bind:value={f.description}
								maxlength={500}
								disabled={!canEdit}
							/>
						</SectionBlock>

						<SectionBlock
							title="Regional"
							hint="Used for scheduling, quotes, and every amount your business writes."
							form
							level={3}
						>
							<div class="business-profile__field-group">
								<TimezonePicker id="bp-timezone" bind:value={f.timezone} required />
								{#if !timezoneConfirmed}
									<p class="business-profile__suggestion">
										{f.timezone === suggestedTimezone
											? 'Detected from your browser — confirm it to save.'
											: 'Not confirmed yet.'}
										<button type="button" onclick={markTimezoneConfirmed} disabled={!canEdit}
											>Confirm timezone</button
										>
									</p>
								{/if}
							</div>

							<div class="business-profile__field-group">
								<Select
									id="bp-currency"
									ariaLabel="Currency"
									placeholder="Currency"
									options={COMMON_CURRENCIES.map((c) => ({
										value: c.code,
										label: `${c.code} — ${c.label}`
									}))}
									bind:value={f.currency_code}
									disabled={!canEdit || query.data.currency_locked}
								/>
								{#if query.data.currency_locked}
									<p class="business-profile__locked">
										Currency is locked because a quote has already been sent to a customer.
									</p>
								{:else if !currencyConfirmed}
									<p class="business-profile__suggestion">
										Not confirmed yet.
										<button type="button" onclick={markCurrencyConfirmed} disabled={!canEdit}
											>Confirm currency</button
										>
									</p>
								{/if}
							</div>
						</SectionBlock>
					</div>

					<div class="business-profile__column">
						<SectionBlock
							title="Address"
							hint="Where your business is based. Optional."
							form
							level={3}
						>
							<Input
								id="bp-address1"
								label="Address line 1"
								bind:value={f.address_line1}
								disabled={!canEdit}
							/>
							<Input
								id="bp-address2"
								label="Address line 2"
								bind:value={f.address_line2}
								disabled={!canEdit}
							/>
							<div class="business-profile__row business-profile__row--three">
								<Input id="bp-city" label="City" bind:value={f.city} disabled={!canEdit} />
								<Input
									id="bp-region"
									label="State / region"
									bind:value={f.region}
									disabled={!canEdit}
								/>
								<Input
									id="bp-postal"
									label="Postal code"
									bind:value={f.postal_code}
									disabled={!canEdit}
								/>
							</div>
							<Select
								id="bp-country"
								ariaLabel="Country"
								placeholder="Country"
								options={COUNTRIES}
								bind:value={f.country_code}
								disabled={!canEdit}
							/>
							<Toggle
								id="bp-address-public"
								label="Show the full address to customers"
								description="Off shows only the city and state on quotes, invoices, and the client portal."
								labelSide="start"
								bind:checked={f.address_is_public}
								disabled={!canEdit}
							/>
						</SectionBlock>
					</div>
				</div>
			{/if}
		{/snippet}

		{#snippet actions()}
			{#if canEdit}
				<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
				<Button
					onclick={() => void save().finally(() => layout?.revealError())}
					disabled={!dirty || saving || timezoneBlocked || currencyBlocked}
					loading={saving}>Save</Button
				>
			{/if}
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.business-profile {
		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}
		&__columns {
			display: grid;
			grid-template-columns: 1fr 1fr;
			align-items: start;
			gap: var(--space-large);
		}
		&__column {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			min-width: 0;
		}
		&__row {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);

			&--three {
				grid-template-columns: repeat(3, minmax(0, 1fr));
			}
		}
		&__field-group {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}
		&__suggestion,
		&__locked {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__suggestion button {
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-large);
			color: var(--color-interactive);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__suggestion button:hover {
			background: var(--color-surface--hover);
		}
	}
	@media (max-width: 1079px) {
		.business-profile__columns {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 767px) {
		.business-profile__row,
		.business-profile__row--three {
			grid-template-columns: 1fr;
		}
	}
</style>
