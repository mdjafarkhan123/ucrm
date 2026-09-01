<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import ClientTagSelect from './ClientTagSelect.svelte';
	import CommunicationSettingsDialog from './CommunicationSettingsDialog.svelte';
	import {
		fetchDuplicateCandidates,
		saveClient,
		ClientWriteError,
		type ClientPreferences,
		type ClientWriteValues,
		type DuplicateCandidates
	} from '$lib/clients/api';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';

	// Creating a client only. An existing client is edited block by block on its own page, so there is
	// exactly one way to edit and no journey that lands the office back on a creation form.
	let {
		onSaved,
		onCancel
	}: {
		onSaved: (client: { id: string; display_name: string }, andAnother: boolean) => void;
		onCancel: () => void;
	} = $props();

	const queryClient = useQueryClient();

	const DEFAULT_PREFERENCES: ClientPreferences = {
		contact_policy: 'allow',
		quote_follow_ups: true,
		invoice_reminders: true,
		appointment_reminders: true,
		job_follow_ups: true,
		review_requests: true,
		marketing: false
	};

	const LEAD_SOURCES = [
		'Referral',
		'Google search',
		'Website',
		'Social media',
		'Repeat customer',
		'Drive by',
		'Other'
	];

	const COUNTRIES = [
		{ value: 'US', label: 'United States' },
		{ value: 'CA', label: 'Canada' },
		{ value: 'GB', label: 'United Kingdom' },
		{ value: 'AU', label: 'Australia' }
	];

	type FormState = {
		client_type: 'person' | 'company';
		lifecycle_status: 'lead' | 'customer';
		first_name: string;
		last_name: string;
		company_name: string;
		email: string;
		phone: string;
		lead_source: string;
		initial_note: string;
		address_line1: string;
		address_line2: string;
		postal_code: string;
		city: string;
		state_region: string;
		country: string;
		preferences: ClientPreferences;
		tag_ids: string[];
	};

	function blankForm(): FormState {
		return {
			client_type: 'person',
			lifecycle_status: 'lead',
			first_name: '',
			last_name: '',
			company_name: '',
			email: '',
			phone: '',
			lead_source: '',
			initial_note: '',
			address_line1: '',
			address_line2: '',
			postal_code: '',
			city: '',
			state_region: '',
			country: 'US',
			preferences: { ...DEFAULT_PREFERENCES },
			tag_ids: []
		};
	}

	let form = $state<FormState>(untrack(() => blankForm()));
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();
	let settingsOpen = $state(false);
	let attachmentsCard = $state<AttachmentsCard>();
	let pendingFileCount = $state(0);

	// Save stays quiet until something has actually changed. The baseline is the empty form on a create
	// and the loaded client on an edit, and it moves forward every time a save lands.
	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(form)));
	const isDirty = $derived(snapshot(form) !== baseline || pendingFileCount > 0);

	// Set when a create succeeded but its files did not. The client exists from that moment on, so every
	// later press of Save has to update it instead of creating a second one.
	let savedClientId = $state('');
	const targetClientId = $derived(savedClientId);

	const isCompany = $derived(form.client_type === 'company');

	// Any address field filled means the office intends to save a property, so the server checks the
	// whole address rather than quietly dropping a half-typed one.
	const hasAnyAddress = $derived(
		Boolean(
			form.address_line1.trim() ||
			form.address_line2.trim() ||
			form.postal_code.trim() ||
			form.city.trim() ||
			form.state_region.trim()
		)
	);

	function buildValues(): ClientWriteValues {
		return {
			client_type: form.client_type,
			lifecycle_status: form.lifecycle_status,
			first_name: form.first_name.trim(),
			last_name: form.last_name.trim(),
			company_name: form.company_name.trim(),
			email: form.email.trim(),
			phone: form.phone.trim(),
			lead_source: form.lead_source,
			initial_note: form.initial_note.trim(),
			preferences: form.preferences,
			tag_ids: form.tag_ids,
			...(hasAnyAddress
				? {
						property: {
							address_line1: form.address_line1.trim(),
							address_line2: form.address_line2.trim(),
							city: form.city.trim(),
							state_region: form.state_region.trim(),
							postal_code: form.postal_code.trim(),
							country: form.country
						}
					}
				: {})
		};
	}

	// --- Duplicate warnings ---------------------------------------------------------------------------

	let duplicateProbe = $state({ email: '', phone: '', name: '', address: '' });

	// Waits for a pause in typing before asking, so a half-typed email does not fire a lookup per keystroke.
	$effect(() => {
		const email = form.email.trim();
		const phone = form.phone.trim();
		const name = isCompany
			? form.company_name.trim()
			: [form.first_name.trim(), form.last_name.trim()].filter(Boolean).join(' ');
		const address = form.address_line1.trim();

		const handle = setTimeout(() => {
			duplicateProbe = { email, phone, name: name.length >= 3 ? name : '', address };
		}, 500);
		return () => clearTimeout(handle);
	});

	const probeHasInput = $derived(
		Boolean(
			duplicateProbe.email || duplicateProbe.phone || duplicateProbe.name || duplicateProbe.address
		)
	);

	const duplicatesQuery = createQuery(() => ({
		queryKey: ['clients', 'duplicates', duplicateProbe, targetClientId || null],
		// Once a create has landed, the new client stops counting as its own duplicate.
		queryFn: () =>
			fetchDuplicateCandidates({ ...duplicateProbe, excludeClientId: targetClientId || undefined }),
		enabled: probeHasInput,
		// A duplicate answer goes stale slowly, but each pause in typing makes its own cache entry, so
		// they are dropped soon after the form stops asking for them.
		staleTime: 30_000,
		gcTime: 60_000
	}));

	const exactMatches = $derived(duplicatesQuery.data?.exact ?? []);
	const similarMatches = $derived(duplicatesQuery.data?.similar ?? []);

	function matchLabel(match: DuplicateCandidates['exact'][number]) {
		return match.matched_on === 'email' ? 'email address' : 'phone number';
	}

	// --- Saving ---------------------------------------------------------------------------------------

	async function submit(andAnother: boolean) {
		if (saving || !isDirty) return;
		saving = true;
		fieldErrors = {};
		formError = '';

		try {
			const client = await saveClient(buildValues(), targetClientId || undefined);

			// The list, the filtered lists, and this client's own record all move on a save.
			await queryClient.invalidateQueries({ queryKey: ['clients', 'list'] });
			if (targetClientId) {
				await queryClient.invalidateQueries({ queryKey: ['clients', 'detail', targetClientId] });
				if (form.initial_note.trim())
					await queryClient.invalidateQueries({
						queryKey: ['collaboration', 'notes', 'client', targetClientId]
					});
				await queryClient.invalidateQueries({
					queryKey: ['collaboration', 'tag-assignments', 'client', targetClientId]
				});
				await queryClient.invalidateQueries({
					queryKey: ['collaboration', 'activity', 'client', targetClientId]
				});
			}

			// Files only upload once the client exists. A failure here leaves the client saved, so the
			// office stays on this page with a Retry beside each file rather than losing the save.
			const failedUploads = (await attachmentsCard?.saveAll(client.id)) ?? 0;
			if (failedUploads > 0) {
				savedClientId = client.id;
				// The client itself is saved, so the fields are clean again; only the stuck files stay dirty.
				baseline = snapshot(form);
				formError =
					failedUploads === 1
						? 'The client was saved, but one file did not upload. Retry it below.'
						: `The client was saved, but ${failedUploads} files did not upload. Retry them below.`;
				return;
			}

			if (andAnother) form = blankForm();
			baseline = snapshot(form);
			onSaved(client, andAnother);
		} catch (error) {
			if (error instanceof ClientWriteError) {
				fieldErrors = error.fieldErrors;
				formError =
					error.duplicates.length > 0
						? `${error.duplicates[0].display_name} already uses that ${matchLabel(error.duplicates[0])}.`
						: error.message;
			} else {
				formError = error instanceof Error ? error.message : 'That client could not be saved.';
			}
		} finally {
			saving = false;
		}
	}

	const leadSourceOptions = $derived([
		{ value: '', label: 'Select lead source' },
		...LEAD_SOURCES.map((source) => ({ value: source, label: source })),
		// Keeps a source saved before this list existed visible instead of silently blanking it.
		...(form.lead_source && !LEAD_SOURCES.includes(form.lead_source)
			? [{ value: form.lead_source, label: form.lead_source }]
			: [])
	]);

	const CLIENT_TYPE_OPTIONS = [
		{ value: 'person', label: 'Person' },
		{ value: 'company', label: 'Company' }
	];

	const LIFECYCLE_OPTIONS = [
		{ value: 'lead', label: 'Lead' },
		{ value: 'customer', label: 'Customer' }
	];

	const policyOptions = [
		{ value: 'allow', label: 'Allow all messages' },
		{ value: 'no_marketing', label: 'No marketing messages' },
		{ value: 'do_not_disturb', label: 'Do not disturb' }
	];

	const title = 'New client';
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<form
	class="client-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit(false).finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout {title} icon={userIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<SectionBlock title="Primary details" icon={userIcon} variant="filled" form>
				<div class="client-form__choices">
					<SegmentedControl
						label="Client type"
						value={form.client_type}
						options={CLIENT_TYPE_OPTIONS}
						onchange={(next) => (form.client_type = next as 'person' | 'company')}
					/>
					<SegmentedControl
						label="Status"
						value={form.lifecycle_status}
						options={LIFECYCLE_OPTIONS}
						onchange={(next) => (form.lifecycle_status = next as 'lead' | 'customer')}
					/>
				</div>

				<div class="client-form__grid">
					{#if isCompany}
						<div class="client-form__grid-full">
							<Input
								id="client-company-name"
								label="Company name"
								required
								bind:value={form.company_name}
								invalid={Boolean(fieldErrors.company_name)}
								errorMessage={fieldErrors.company_name ?? ''}
								autocomplete="organization"
							/>
						</div>
						<Input
							id="client-first-name"
							label="Contact first name (optional)"
							bind:value={form.first_name}
							invalid={Boolean(fieldErrors.first_name)}
							errorMessage={fieldErrors.first_name ?? ''}
							autocomplete="given-name"
						/>
						<Input
							id="client-last-name"
							label="Contact last name (optional)"
							bind:value={form.last_name}
							invalid={Boolean(fieldErrors.last_name)}
							errorMessage={fieldErrors.last_name ?? ''}
							autocomplete="family-name"
						/>
					{:else}
						<Input
							id="client-first-name"
							label="First name"
							required
							bind:value={form.first_name}
							invalid={Boolean(fieldErrors.first_name)}
							errorMessage={fieldErrors.first_name ?? ''}
							autocomplete="given-name"
						/>
						<Input
							id="client-last-name"
							label="Last name"
							required
							bind:value={form.last_name}
							invalid={Boolean(fieldErrors.last_name)}
							errorMessage={fieldErrors.last_name ?? ''}
							autocomplete="family-name"
						/>
					{/if}

					<Input
						id="client-email"
						label="Email address"
						type="email"
						bind:value={form.email}
						invalid={Boolean(fieldErrors.email)}
						errorMessage={fieldErrors.email ?? ''}
						autocomplete="email"
					/>
					<Input
						id="client-phone"
						label="Phone number"
						type="tel"
						bind:value={form.phone}
						invalid={Boolean(fieldErrors.phone)}
						errorMessage={fieldErrors.phone ?? ''}
						autocomplete="tel"
					/>

					{#if !isCompany}
						<Input
							id="client-company-name"
							label="Company name (optional)"
							bind:value={form.company_name}
							invalid={Boolean(fieldErrors.company_name)}
							errorMessage={fieldErrors.company_name ?? ''}
							autocomplete="organization"
						/>
					{/if}

					<div class="client-form__policy">
						<label class="client-form__policy-label" for="client-contact-policy">
							Communication setting
						</label>
						<div class="client-form__policy-row">
							<Select
								id="client-contact-policy"
								value={form.preferences.contact_policy}
								options={policyOptions}
								onchange={(value) =>
									(form.preferences = {
										...form.preferences,
										contact_policy: value as ClientPreferences['contact_policy']
									})}
							/>
							<button
								type="button"
								class="client-form__configure"
								onclick={() => (settingsOpen = true)}
							>
								<span aria-hidden="true">{@html settingsIcon}</span>Configure
							</button>
						</div>
					</div>
				</div>

				{#if exactMatches.length > 0}
					<p class="client-form__warning client-form__warning--blocking" role="alert">
						<span aria-hidden="true">{@html alertTriangleIcon}</span>
						{exactMatches[0].display_name} already uses that {matchLabel(exactMatches[0])}. Change
						it before saving.
					</p>
				{:else if similarMatches.length > 0}
					<p class="client-form__warning">
						<span aria-hidden="true">{@html alertTriangleIcon}</span>
						Looks similar to {similarMatches
							.slice(0, 3)
							.map((match) => match.display_name)
							.join(', ')}. Carry on if this is someone new.
					</p>
				{/if}
			</SectionBlock>

			<SectionBlock
				title="Client address"
				icon={mapPinIcon}
				hint="Optional. Filling this in creates the client's first property."
				form
			>
				<div class="client-form__grid">
					<Input
						id="client-address-line1"
						label="Street address 1"
						required={hasAnyAddress}
						bind:value={form.address_line1}
						invalid={Boolean(fieldErrors['property.address_line1'])}
						errorMessage={fieldErrors['property.address_line1'] ?? ''}
						autocomplete="address-line1"
					/>
					<Input
						id="client-address-line2"
						label="Street address 2 (optional)"
						bind:value={form.address_line2}
						autocomplete="address-line2"
					/>
					<Input
						id="client-postal-code"
						label="Postal code"
						bind:value={form.postal_code}
						invalid={Boolean(fieldErrors['property.postal_code'])}
						errorMessage={fieldErrors['property.postal_code'] ?? ''}
						autocomplete="postal-code"
					/>
					<Input
						id="client-city"
						label="City"
						required={hasAnyAddress}
						bind:value={form.city}
						invalid={Boolean(fieldErrors['property.city'])}
						errorMessage={fieldErrors['property.city'] ?? ''}
						autocomplete="address-level2"
					/>
					<Input
						id="client-state"
						label="State or region"
						bind:value={form.state_region}
						invalid={Boolean(fieldErrors['property.state_region'])}
						errorMessage={fieldErrors['property.state_region'] ?? ''}
						autocomplete="address-level1"
					/>
					<div class="client-form__policy">
						<label class="client-form__policy-label" for="client-country">Country</label>
						<Select id="client-country" bind:value={form.country} options={COUNTRIES} />
					</div>
				</div>
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<RailCard title="Lead source">
				<Select
					id="client-lead-source"
					value={form.lead_source}
					options={leadSourceOptions}
					placeholder="Select lead source"
					onchange={(value) => (form.lead_source = value)}
				/>
			</RailCard>

			<RailCard title="Tags" count={form.tag_ids.length}>
				<ClientTagSelect bind:tagIds={form.tag_ids} />
			</RailCard>

			<FormNotesCard
				id="client-initial-note"
				bind:value={form.initial_note}
				error={fieldErrors.initial_note ?? ''}
			/>

			<AttachmentsCard
				bind:this={attachmentsCard}
				onPendingChange={(count) => (pendingFileCount = count)}
				entityType="client"
				entityId={targetClientId || undefined}
			/>
		{/snippet}

		{#snippet actions()}
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<div class="client-form__actions-primary">
				{#if !savedClientId}
					<Button
						variant="secondary"
						onclick={() => void submit(true).finally(() => layout?.revealError())}
						disabled={saving || !isDirty}
					>
						Save & create another
					</Button>
				{/if}
				<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
					{savedClientId ? 'Save changes' : 'Save client'}
				</Button>
			</div>
		{/snippet}
	</RecordFormLayout>
</form>

<CommunicationSettingsDialog
	open={settingsOpen}
	bind:preferences={form.preferences}
	onClose={() => (settingsOpen = false)}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__choices {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-large);
		}

		&__grid {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__grid-full {
			grid-column: 1 / -1;
		}

		&__policy {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__policy-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__policy-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__configure {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-small) var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);
			font: inherit;
			font-weight: 600;
			white-space: nowrap;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__warning {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface--active);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
				flex: 0 0 auto;
			}

			&--blocking {
				color: var(--color-critical--onSurface);
				background: var(--color-critical--surface);
			}
		}

		&__actions-primary {
			display: flex;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.client-form__grid {
			grid-template-columns: 1fr;
		}
		.client-form__actions-primary {
			flex-direction: column;
		}
	}
</style>
