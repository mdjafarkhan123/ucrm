<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import BusinessIdentityCard from '$lib/components/settings/profile/BusinessIdentityCard.svelte';
	import ProfileFact from '$lib/components/settings/profile/ProfileFact.svelte';
	import ProfileSectionCard from '$lib/components/settings/profile/ProfileSectionCard.svelte';
	import ServiceAreaMap from '$lib/components/settings/profile/ServiceAreaMap.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsBusiness,
		settingsBusinessKey,
		settingsHomeKey,
		saveBusinessProfile,
		saveServiceAreaRadius,
		isSaveConflict,
		COMMON_CURRENCIES,
		type BusinessProfile,
		type SettingsBusiness
	} from '$lib/settings/api';
	import { amountAndDateSample, timeThere, timezoneLabel } from '$lib/settings/profile-format';
	import { TRADES } from '$lib/settings/trades';
	import { countryDisplayName } from '$lib/settings/country-names';
	import storeIcon from '@tabler/icons/outline/building-store.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import clockNowIcon from '@tabler/icons/outline/clock-hour-3.svg?raw';
	import currencyIcon from '@tabler/icons/outline/currency-dollar.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import radarIcon from '@tabler/icons/outline/radar.svg?raw';
	import mapPinHomeIcon from '@tabler/icons/outline/map-pin-2.svg?raw';
	import globeIcon from '@tabler/icons/outline/world.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsBusinessKey,
		queryFn: fetchSettingsBusiness
	}));

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
		/** Miles, or '' while the field is empty. Kept as text so a person can clear it without it snapping to 0. */
		serviceAreaRadius: string;
	};

	// The page saves one section at a time. Each section owns these fields; the save command still takes the
	// whole profile, so a section's save sends the saved values for every field it does not own.
	type SectionKey = 'identity' | 'contact' | 'regional' | 'where';
	const SECTION_FIELDS: Record<SectionKey, (keyof FormState)[]> = {
		identity: ['name', 'trade', 'tradeOther', 'description'],
		contact: ['phone', 'website'],
		regional: ['timezone', 'currency_code'],
		where: [
			'address_line1',
			'address_line2',
			'city',
			'region',
			'postal_code',
			'country_code',
			'address_is_public',
			'serviceAreaRadius'
		]
	};
	const FIELD_LABELS: Partial<Record<keyof FormState, string>> = {
		name: 'Business name',
		trade: 'Trade',
		tradeOther: 'Trade',
		description: 'Tagline',
		phone: 'Main phone',
		website: 'Website',
		timezone: 'Time zone',
		currency_code: 'Currency',
		address_line1: 'Street address',
		address_line2: 'Unit',
		city: 'City',
		region: 'Province / state',
		postal_code: 'Postal code',
		country_code: 'Country',
		address_is_public: 'Show full address',
		serviceAreaRadius: 'Service area'
	};
	const SECTION_TITLES: Record<SectionKey, string> = {
		identity: 'Name and trade',
		contact: 'Contact',
		regional: 'Time zone and currency',
		where: 'Where you work'
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
			currency_code: profile.currency_code,
			serviceAreaRadius:
				profile.service_area_radius_miles !== null ? String(profile.service_area_radius_miles) : ''
		};
	}

	function tradeOf(f: FormState): string {
		return f.trade === 'Other' ? f.tradeOther.trim() : f.trade;
	}

	let form = $state<FormState | null>(null);
	let openSection = $state<SectionKey | null>(null);
	let savingSection = $state<SectionKey | 'confirm' | null>(null);
	let errorMessage = $state('');
	let conflict = $state<{
		section: SectionKey;
		who: string;
		when: string;
		theirs: string[] | null;
		checking: boolean;
	} | null>(null);
	let pendingSection = $state<SectionKey | null>(null);
	let now = $state(new Date());

	const profile = $derived(query.data?.profile ?? null);
	const saved = $derived(profile ? toForm(profile) : null);
	const canEdit = $derived(query.data?.permissions.edit ?? false);
	const radiusReady = $derived(profile?.location_ready ?? false);

	// First load fills the draft; after that every section that is not open follows what is saved, so a save
	// elsewhere or a refetch shows through without touching what someone is typing.
	$effect(() => {
		const next = saved;
		if (!next) return;
		untrack(() => {
			if (!form) {
				form = { ...next };
				return;
			}
			const draft = { ...form };
			for (const key of Object.keys(SECTION_FIELDS) as SectionKey[]) {
				if (key === openSection) continue;
				for (const field of SECTION_FIELDS[key]) (draft[field] as unknown) = next[field];
			}
			form = draft;
		});
	});

	onMount(() => {
		const timer = setInterval(() => (now = new Date()), 30_000);
		return () => clearInterval(timer);
	});

	function sectionDirty(key: SectionKey): boolean {
		if (!form || !saved) return false;
		return SECTION_FIELDS[key].some((field) => form![field] !== saved[field]);
	}
	const anyDirty = $derived(
		(['identity', 'contact', 'regional', 'where'] as SectionKey[]).some(sectionDirty)
	);

	function discard(key: SectionKey) {
		if (!form || !saved) return;
		const draft = { ...form };
		for (const field of SECTION_FIELDS[key]) (draft[field] as unknown) = saved[field];
		form = draft;
		if (conflict?.section === key) conflict = null;
		errorMessage = '';
	}

	function edit(key: SectionKey) {
		if (openSection && openSection !== key && sectionDirty(openSection)) {
			pendingSection = key;
			return;
		}
		if (openSection) discard(openSection);
		openSection = key;
		errorMessage = '';
		conflict = null;
	}
	function cancel(key: SectionKey) {
		discard(key);
		openSection = null;
	}
	async function saveAndSwitch() {
		const from = openSection;
		const to = pendingSection;
		pendingSection = null;
		if (!from || !to) return;
		const ok = await save(from);
		if (ok) {
			openSection = to;
			errorMessage = '';
		}
	}
	function dropAndSwitch() {
		const from = openSection;
		const to = pendingSection;
		pendingSection = null;
		if (from) discard(from);
		if (to) {
			openSection = to;
			errorMessage = '';
		}
	}

	beforeNavigate((navigation) => {
		if (!anyDirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!anyDirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	// An empty radius means "not set yet" and is fine to save as-is. Once a radius is set, though, the
	// database command that saves it has no way to clear one back to null — so blanking a set field blocks
	// Save rather than silently failing at the network call.
	const radiusInvalid = $derived.by(() => {
		if (!form || !saved) return false;
		const raw = form.serviceAreaRadius.trim();
		if (raw === '') return saved.serviceAreaRadius.trim() !== '';
		const n = Number(raw);
		return !Number.isFinite(n) || n < 0.1 || n > 500;
	});

	function saveDisabled(key: SectionKey): boolean {
		if (!form) return true;
		if (key === 'identity') return !sectionDirty(key) || form.name.trim().length < 2;
		if (key === 'where') return !sectionDirty(key) || radiusInvalid;
		return !sectionDirty(key);
	}

	function whenText(iso: string | null): string {
		if (!iso) return 'just now';
		const date = new Date(iso);
		if (Number.isNaN(date.getTime())) return 'just now';
		return `at ${new Intl.DateTimeFormat('en', { hour: 'numeric', minute: '2-digit' }).format(date)}`;
	}

	type Confirmations = { timezone: boolean; currency: boolean };

	// Sends the whole profile, with this section's draft over the saved values. Returns the new revision, or
	// null when the save did not land (an error message or a "someone saved first" notice is then showing).
	async function persist(
		section: SectionKey | null,
		confirm: Confirmations
	): Promise<number | null> {
		if (!form || !saved || !profile) return null;
		const draft: FormState = { ...saved };
		if (section)
			for (const field of SECTION_FIELDS[section]) (draft[field] as unknown) = form[field];

		const result = await saveBusinessProfile({
			expected_revision: profile.revision,
			name: draft.name,
			trade: tradeOf(draft),
			phone: draft.phone,
			website: draft.website,
			description: draft.description,
			address_line1: draft.address_line1,
			address_line2: draft.address_line2,
			city: draft.city,
			region: draft.region,
			postal_code: draft.postal_code,
			country_code: draft.country_code,
			address_is_public: draft.address_is_public,
			timezone: draft.timezone,
			currency_code: draft.currency_code,
			confirm_timezone: confirm.timezone,
			confirm_currency: confirm.currency
		}).catch((error: Error) => {
			errorMessage = error.message;
			return null;
		});
		if (!result) return null;
		if (isSaveConflict(result)) {
			if (section) {
				conflict = {
					section,
					who: result.editor_name ?? 'Someone else',
					when: whenText(result.edited_at),
					theirs: null,
					checking: false
				};
			} else {
				errorMessage = `${result.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version.`;
			}
			return null;
		}
		return result.profile_revision;
	}

	// Patches the cached profile in place before refetching: an immediate second save must see this save's
	// revision, not a stale one from before the request.
	function patchProfile(
		draft: FormState,
		revision: number,
		confirm: Confirmations,
		radius: string
	) {
		queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
			current
				? {
						...current,
						profile: {
							...current.profile,
							name: draft.name,
							trade: tradeOf(draft) || null,
							phone: draft.phone || null,
							website: draft.website || null,
							description: draft.description || null,
							address_line1: draft.address_line1 || null,
							address_line2: draft.address_line2 || null,
							city: draft.city || null,
							region: draft.region || null,
							postal_code: draft.postal_code || null,
							country_code: draft.country_code || null,
							address_is_public: draft.address_is_public,
							timezone: draft.timezone,
							currency_code: draft.currency_code,
							timezone_confirmed: current.profile.timezone_confirmed || confirm.timezone,
							currency_confirmed: current.profile.currency_confirmed || confirm.currency,
							revision,
							service_area_radius_miles: radius ? Number(radius) : null
						}
					}
				: current
		);
	}

	async function refreshAfterSave() {
		await queryClient.invalidateQueries({ queryKey: settingsBusinessKey });
		await queryClient.invalidateQueries({ queryKey: settingsHomeKey });
	}

	async function save(section: SectionKey): Promise<boolean> {
		if (!form || !saved || !profile) return false;
		savingSection = section;
		errorMessage = '';
		conflict = null;
		try {
			const radiusChanged =
				section === 'where' && form.serviceAreaRadius !== saved.serviceAreaRadius;
			const profileChanged = SECTION_FIELDS[section].some(
				(field) => field !== 'serviceAreaRadius' && form![field] !== saved[field]
			);
			// Saving the time zone section is the person choosing it; a changed currency is chosen too.
			const confirm: Confirmations = {
				timezone: section === 'regional' || profile.timezone_confirmed,
				currency:
					(section === 'regional' && form.currency_code !== saved.currency_code) ||
					profile.currency_confirmed
			};

			let revision = profile.revision;
			if (profileChanged) {
				const next = await persist(section, confirm);
				if (next === null) return false;
				revision = next;
			}

			let radius = saved.serviceAreaRadius;
			// The radius saves through its own command (it is not part of the profile save), sharing the same
			// revision counter — so it runs once the profile save above has landed, with the fresh revision.
			if (radiusChanged && radiusReady) {
				const result = await saveServiceAreaRadius({
					expected_revision: revision,
					radius_miles: Number(form.serviceAreaRadius)
				}).catch((error: Error) => {
					errorMessage = error.message;
					return null;
				});
				if (!result) return false;
				if (isSaveConflict(result)) {
					conflict = {
						section,
						who: result.editor_name ?? 'Someone else',
						when: whenText(result.edited_at),
						theirs: null,
						checking: false
					};
					return false;
				}
				revision = result.profile_revision;
				radius = String(result.service_area_radius_miles);
			}

			const draft: FormState = { ...saved };
			for (const field of SECTION_FIELDS[section]) (draft[field] as unknown) = form[field];
			patchProfile(draft, revision, confirm, radius);
			openSection = openSection === section ? null : openSection;
			toast.success(`${SECTION_TITLES[section]} saved.`);
			await refreshAfterSave();
			return true;
		} finally {
			savingSection = null;
		}
	}

	// Confirm on a closed card: the value stays as it is and only the "someone chose this" mark is saved.
	async function confirmValue(kind: 'timezone' | 'currency') {
		if (!profile || savingSection) return;
		savingSection = 'confirm';
		errorMessage = '';
		try {
			const confirm: Confirmations = {
				timezone: kind === 'timezone' || profile.timezone_confirmed,
				currency: kind === 'currency' || profile.currency_confirmed
			};
			const revision = await persist(null, confirm);
			if (revision === null) {
				if (errorMessage) toast.error(errorMessage);
				return;
			}
			if (saved) patchProfile(saved, revision, confirm, saved.serviceAreaRadius);
			toast.success(kind === 'timezone' ? 'Time zone confirmed.' : 'Currency confirmed.');
			await refreshAfterSave();
		} finally {
			savingSection = null;
		}
	}

	// "See their version": fetch what is saved now, say which of this section's fields the other person
	// changed, and let this save go over it knowingly. The person's own draft stays in the fields.
	async function seeTheirs(section: SectionKey) {
		if (!conflict || !form || !saved) return;
		conflict = { ...conflict, checking: true };
		const before = saved;
		await queryClient.invalidateQueries({ queryKey: settingsBusinessKey });
		const fresh = queryClient.getQueryData<SettingsBusiness>(settingsBusinessKey)?.profile;
		if (!fresh) {
			conflict = conflict ? { ...conflict, checking: false } : null;
			return;
		}
		const theirs = toForm(fresh);
		const lines = SECTION_FIELDS[section]
			.filter((field) => theirs[field] !== before[field])
			.map((field) => {
				const value = theirs[field];
				const shown =
					typeof value === 'boolean' ? (value ? 'Yes' : 'No') : String(value).trim() || 'Empty';
				return `${FIELD_LABELS[field] ?? field}: ${shown}`;
			});
		conflict = {
			...conflict,
			theirs: lines.length ? lines : ['Nothing in this section changed; their edit was elsewhere.'],
			checking: false
		};
	}

	const lastChanged = $derived.by(() => {
		const editor = profile?.last_editor;
		if (!editor) return '';
		const at = editor.at
			? new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric' }).format(
					new Date(editor.at)
				)
			: '';
		return `Last changed by ${editor.name ?? 'a teammate'}${at ? ` · ${at}` : ''}`;
	});

	const suggestedTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
	const countryName = (code: string) => (code ? countryDisplayName(code) : '');
	const placeOf = (f: FormState) => [f.city, f.region].filter(Boolean).join(', ');
	function addressOf(f: FormState): string {
		const street = [f.address_line1, f.address_line2].filter(Boolean).join(', ');
		const rest = [f.city, [f.region, f.postal_code].filter(Boolean).join(' ')]
			.filter(Boolean)
			.join(', ');
		return [street, rest, countryName(f.country_code)].filter(Boolean).join(', ');
	}
	function currencyLabel(code: string): string {
		const known = COMMON_CURRENCIES.find((c) => c.code === code);
		return known ? `${code} · ${known.label}` : code;
	}
	const inputsDisabled = $derived(!canEdit);
</script>

<svelte:head><title>Business profile · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	{#if query.isPending || !form || !saved || !profile}
		{#if query.isError}
			<ErrorState
				description="Business profile could not be loaded."
				retry={() => query.refetch()}
			/>
		{:else}
			<LoadingSkeleton variant="card" rows={4} />
		{/if}
	{:else}
		{@const data = query.data!}
		{@const f = form}
		{@const radiusMiles =
			f.serviceAreaRadius.trim() && !radiusInvalid ? Number(f.serviceAreaRadius) : null}
		<div class="business-profile">
			<div class="business-profile__head">
				<Breadcrumbs
					items={[
						{ label: 'Settings', href: resolve('/(app)/settings') },
						{ label: 'Business profile', icon: storeIcon }
					]}
				/>
				<PageHeader
					icon={storeIcon}
					tone="inactive"
					title="Business profile"
					description="Your name, contact details, address, time zone and currency. Customers see these on everything you send."
				>
					{#snippet actions()}
						{#if lastChanged}
							<p class="business-profile__changed">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
								<span aria-hidden="true">{@html historyIcon}</span>{lastChanged}
							</p>
						{/if}
					{/snippet}
				</PageHeader>
			</div>

			{#if !canEdit}
				<Banner type="notice" icon={lockIcon}>
					{`Only owners and administrators can change this.${
						profile.last_editor
							? ` Last changed by ${profile.last_editor.name ?? 'a teammate'}.`
							: ''
					}`}
				</Banner>
			{/if}

			{#snippet errorBanner()}
				{#if errorMessage && !conflict}<Banner type="error">{errorMessage}</Banner>{/if}
			{/snippet}

			<BusinessIdentityCard
				name={saved.name}
				trade={tradeOf(saved) || null}
				city={saved.city || null}
				tagline={saved.description || null}
				logoUrl={data.branding.logo_url}
				complete={data.readiness.profile.complete}
				open={openSection === 'identity'}
				{canEdit}
				saving={savingSection === 'identity'}
				saveDisabled={saveDisabled('identity')}
				conflict={conflict?.section === 'identity' ? conflict : null}
				onEdit={() => edit('identity')}
				onCancel={() => cancel('identity')}
				onSave={() => void save('identity')}
				onSeeTheirs={() => void seeTheirs('identity')}
			>
				{#snippet form()}
					{@render errorBanner()}
					<div class="business-profile__row">
						<Input
							id="bp-name"
							label="Business name"
							bind:value={f.name}
							required
							disabled={inputsDisabled}
						/>
						<Select
							id="bp-trade"
							label="Trade"
							placeholder="Trade"
							options={TRADES.map((t) => ({ value: t, label: t }))}
							bind:value={f.trade}
							disabled={inputsDisabled}
						/>
					</div>
					{#if f.trade === 'Other'}
						<Input
							id="bp-trade-other"
							label="Describe your trade"
							bind:value={f.tradeOther}
							disabled={inputsDisabled}
						/>
					{/if}
					<div class="business-profile__field">
						<Textarea
							id="bp-description"
							label="Short description or tagline"
							bind:value={f.description}
							maxlength={500}
							disabled={inputsDisabled}
						/>
						<p class="business-profile__hint">
							Shows under your name on quotes, invoices and the client portal.
						</p>
					</div>
				{/snippet}
			</BusinessIdentityCard>

			<div class="business-profile__pair">
				<ProfileSectionCard
					title="Contact"
					hint="How customers reach you"
					icon={phoneIcon}
					tone="conversation"
					open={openSection === 'contact'}
					{canEdit}
					saving={savingSection === 'contact'}
					saveLabel="Save contact"
					saveDisabled={saveDisabled('contact')}
					footerHint="Only this section is saved"
					conflict={conflict?.section === 'contact' ? conflict : null}
					onEdit={() => edit('contact')}
					onCancel={() => cancel('contact')}
					onSave={() => void save('contact')}
					onSeeTheirs={() => void seeTheirs('contact')}
				>
					{#snippet facts()}
						<ProfileFact
							icon={phoneIcon}
							tone="conversation"
							label="Main phone"
							value={saved.phone || 'Not set'}
						/>
						<ProfileFact
							icon={worldIcon}
							tone="inactive"
							label="Website"
							value={saved.website || 'Not set'}
						/>
					{/snippet}
					{#snippet form()}
						{@render errorBanner()}
						<Input
							id="bp-phone"
							label="Main phone"
							type="tel"
							bind:value={f.phone}
							disabled={inputsDisabled}
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
							<span aria-hidden="true">{@html phoneIcon}</span>
						</Input>
						<Input
							id="bp-website"
							label="Website"
							type="url"
							bind:value={f.website}
							disabled={inputsDisabled}
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
							<span aria-hidden="true">{@html globeIcon}</span>
						</Input>
					{/snippet}
				</ProfileSectionCard>

				<ProfileSectionCard
					title="Time zone and currency"
					hint="Every visit time and every amount you write"
					icon={globeIcon}
					tone="time"
					open={openSection === 'regional'}
					{canEdit}
					saving={savingSection === 'regional'}
					saveLabel="Save"
					saveDisabled={saveDisabled('regional')}
					footerHint="Saving also confirms the time zone"
					conflict={conflict?.section === 'regional' ? conflict : null}
					onEdit={() => edit('regional')}
					onCancel={() => cancel('regional')}
					onSave={() => void save('regional')}
					onSeeTheirs={() => void seeTheirs('regional')}
				>
					{#snippet facts()}
						<ProfileFact
							icon={clockIcon}
							tone="time"
							label="Time zone"
							value={timezoneLabel(saved.timezone, now)}
						>
							{#snippet aside()}
								{#if !profile.timezone_confirmed}
									<StatusBadge status="warning">Not confirmed</StatusBadge>
									{#if canEdit}
										<Button
											variant="secondary"
											size="small"
											loading={savingSection === 'confirm'}
											disabled={savingSection !== null}
											onclick={() => void confirmValue('timezone')}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
											<span aria-hidden="true">{@html checkIcon}</span>Confirm
										</Button>
									{/if}
								{/if}
							{/snippet}
						</ProfileFact>
						<ProfileFact
							icon={clockNowIcon}
							tone="time"
							label="Time there now"
							value={timeThere(saved.timezone, now)}
						/>
						<ProfileFact
							icon={currencyIcon}
							tone="time"
							label="Currency"
							value={currencyLabel(saved.currency_code)}
						>
							{#snippet aside()}
								{#if data.currency_locked}
									<span class="business-profile__locked">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
										<span class="business-profile__lock" aria-hidden="true">{@html lockIcon}</span
										>Locked
									</span>
								{:else if !profile.currency_confirmed}
									<StatusBadge status="warning">Not confirmed</StatusBadge>
									{#if canEdit}
										<Button
											variant="secondary"
											size="small"
											loading={savingSection === 'confirm'}
											disabled={savingSection !== null}
											onclick={() => void confirmValue('currency')}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
											<span aria-hidden="true">{@html checkIcon}</span>Confirm
										</Button>
									{/if}
								{/if}
							{/snippet}
						</ProfileFact>
						<ProfileFact
							icon={hashIcon}
							tone="informative"
							label="Amounts look like"
							value={amountAndDateSample(saved.currency_code, saved.timezone, profile.locale, now)}
						/>
					{/snippet}
					{#snippet note()}
						{#if data.currency_locked}
							<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
							<span class="business-profile__note-icon" aria-hidden="true">{@html infoIcon}</span>
							Currency is locked because a quote has already been sent to a customer, so every record
							stays in {saved.currency_code}.
						{/if}
					{/snippet}
					{#snippet form()}
						{@render errorBanner()}
						<div class="business-profile__field">
							<TimezonePicker id="bp-timezone" bind:value={f.timezone} required />
							<p class="business-profile__hint">
								{#if !profile.timezone_confirmed && f.timezone === suggestedTimezone}
									Detected from your browser. Saving confirms it.
								{:else}
									Visits already booked keep their real time and show in the new zone.
								{/if}
							</p>
						</div>
						<div class="business-profile__field">
							<Select
								id="bp-currency"
								label="Currency"
								placeholder="Currency"
								options={COMMON_CURRENCIES.map((c) => ({
									value: c.code,
									label: `${c.code} · ${c.label}`
								}))}
								bind:value={f.currency_code}
								disabled={inputsDisabled || data.currency_locked}
							/>
							{#if data.currency_locked}
								<p class="business-profile__hint">
									Locked: a quote has already been sent to a customer in {saved.currency_code}.
								</p>
							{/if}
						</div>
					{/snippet}
				</ProfileSectionCard>
			</div>

			<ProfileSectionCard
				title="Where you work"
				hint="Your base and how far you travel"
				icon={mapPinHomeIcon}
				tone="client"
				open={openSection === 'where'}
				{canEdit}
				saving={savingSection === 'where'}
				saveLabel="Save where you work"
				saveDisabled={saveDisabled('where')}
				footerHint="The map moves as you type the address and distance"
				conflict={conflict?.section === 'where' ? conflict : null}
				onEdit={() => edit('where')}
				onCancel={() => cancel('where')}
				onSave={() => void save('where')}
				onSeeTheirs={() => void seeTheirs('where')}
			>
				{#snippet side()}
					<ServiceAreaMap
						miles={openSection === 'where'
							? radiusMiles
							: (profile.service_area_radius_miles ?? null)}
						place={openSection === 'where' ? placeOf(f) : placeOf(saved)}
					/>
				{/snippet}
				{#snippet facts()}
					<ProfileFact
						icon={mapPinIcon}
						tone="client"
						label="Base address"
						value={addressOf(saved) || 'Not set'}
					/>
					<ProfileFact
						icon={eyeOffIcon}
						tone="inactive"
						label="Customers see"
						value={saved.address_is_public
							? addressOf(saved) || 'Not set'
							: `${placeOf(saved) || 'No city yet'} only`}
					>
						{#snippet aside()}
							<StatusBadge status="inactive"
								>{saved.address_is_public ? 'Full address shown' : 'Street hidden'}</StatusBadge
							>
						{/snippet}
					</ProfileFact>
					<ProfileFact
						icon={radarIcon}
						tone="client"
						label="Service area"
						value={profile.service_area_radius_miles
							? `${profile.service_area_radius_miles} miles around your base`
							: 'Not set'}
					/>
				{/snippet}
				{#snippet form()}
					{@render errorBanner()}
					<Input
						id="bp-address1"
						label="Street address"
						bind:value={f.address_line1}
						disabled={inputsDisabled}
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
						<span aria-hidden="true">{@html mapPinIcon}</span>
					</Input>
					<Input
						id="bp-address2"
						label="Unit, suite or floor"
						bind:value={f.address_line2}
						disabled={inputsDisabled}
					/>
					<div class="business-profile__row business-profile__row--three">
						<Input id="bp-city" label="City" bind:value={f.city} disabled={inputsDisabled} />
						<Input
							id="bp-region"
							label="Province / state"
							bind:value={f.region}
							disabled={inputsDisabled}
						/>
						<Input
							id="bp-postal"
							label="Postal code"
							bind:value={f.postal_code}
							disabled={inputsDisabled}
						/>
					</div>
					<div class="business-profile__row">
						<CountryPicker
							id="bp-country"
							label="Country"
							placeholder="Country"
							bind:value={f.country_code}
							disabled={inputsDisabled}
						/>
						{#if radiusReady}
							<Input
								id="bp-service-radius"
								label="Service area (miles from your base)"
								type="number"
								min="0.1"
								max="500"
								step="0.1"
								bind:value={f.serviceAreaRadius}
								disabled={inputsDisabled}
								invalid={radiusInvalid}
								errorMessage={radiusInvalid ? 'Enter a radius between 0.1 and 500 miles.' : ''}
							/>
						{:else}
							<p class="business-profile__hint business-profile__hint--box">
								Save your address first so we can pinpoint your base, then come back to set how far
								you travel.
							</p>
						{/if}
					</div>
					<Toggle
						id="bp-address-public"
						label="Show your full street address to customers"
						description={`Off: quotes, invoices and the client portal show only ${placeOf(f) || 'your city and region'}.`}
						labelSide="start"
						bind:checked={f.address_is_public}
						disabled={inputsDisabled}
					/>
				{/snippet}
			</ProfileSectionCard>
		</div>
	{/if}
</PageContainer>

<ConfirmDialog
	open={pendingSection !== null}
	title={openSection
		? `Save your changes to ${SECTION_TITLES[openSection]}?`
		: 'Save your changes?'}
	tone="warning"
	confirmLabel="Save and continue"
	cancelLabel="Keep editing"
	loading={savingSection !== null}
	onConfirm={() => void saveAndSwitch()}
	onClose={() => (pendingSection = null)}
>
	<p class="business-profile__dialog">
		Only one section opens at a time. Save this one first, or drop what you changed.
	</p>
	<Button variant="quiet" variation="destructive" onclick={dropAndSwitch}>Drop my changes</Button>
</ConfirmDialog>

<style lang="scss">
	.business-profile {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__head :global(.page-header) {
			margin-bottom: 0;
		}
		&__changed {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;

			:global(svg) {
				width: 16px;
				height: 16px;
				color: var(--color-icon--secondary);
			}
		}
		&__pair {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			align-items: stretch;
			gap: var(--space-large);
		}
		&__row {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);

			&--three {
				grid-template-columns: repeat(3, minmax(0, 1fr));
			}
		}
		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}
		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;

			&--box {
				align-self: end;
			}
		}
		&__locked {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-slim);
			background: var(--color-inactive--surface);
			border: var(--border-base) solid var(--color-inactive--surface-edge);
			border-radius: var(--radius-circle);
			color: var(--color-inactive--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__lock,
		&__note-icon {
			display: inline-grid;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__note-icon {
			margin-right: var(--space-small);
			color: var(--color-informative);
			vertical-align: middle;
		}
		&__dialog {
			margin: 0;
		}
	}
	@media (max-width: 1079px) {
		.business-profile__pair {
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
