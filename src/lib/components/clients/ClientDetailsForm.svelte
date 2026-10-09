<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import CommunicationSettingsDialog from './CommunicationSettingsDialog.svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import {
		fetchMessageAutomationStatus,
		messageAutomationStatusKey,
		type ClientIdentityDraft,
		type ClientPreferences
	} from '$lib/clients/api';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';

	// The client's own details, edited where they sit on the client page (Jobber's pattern 1). Its Save
	// writes there and then — the page's bottom bar never sees these fields.
	let {
		values,
		wasCustomer = false,
		saving = false,
		error = '',
		fieldErrors = {},
		onSave,
		onCancel
	}: {
		values: ClientIdentityDraft;
		wasCustomer?: boolean;
		saving?: boolean;
		error?: string;
		fieldErrors?: Record<string, string>;
		onSave: (next: ClientIdentityDraft) => void;
		onCancel: () => void;
	} = $props();

	// The settings dialog says which switches are not sending; warm that answer on hover.
	const queryClient = useQueryClient();
	function prefetchMessageStatus() {
		void queryClient.prefetchQuery({
			queryKey: messageAutomationStatusKey,
			queryFn: fetchMessageAutomationStatus,
			staleTime: 30_000
		});
	}

	// A one-time copy taken when the form mounts. The page mounts it fresh each time it opens, so every
	// visit starts from what is saved, and a background refetch can never overwrite half-typed fields.
	let draft = $state<ClientIdentityDraft>(untrack(() => structuredClone($state.snapshot(values))));
	let settingsOpen = $state(false);

	const isCompany = $derived(draft.client_type === 'company');

	const CLIENT_TYPE_OPTIONS = [
		{ value: 'person', label: 'Person' },
		{ value: 'company', label: 'Company' }
	];

	// A client who has already bought cannot be pushed back to Lead.
	const LIFECYCLE_OPTIONS = $derived([
		{
			value: 'lead',
			label: 'Lead',
			disabled: wasCustomer,
			title: wasCustomer ? 'A customer cannot be turned back into a lead.' : undefined
		},
		{ value: 'customer', label: 'Customer' }
	]);

	const policyOptions = [
		{ value: 'allow', label: 'Allow all messages' },
		{ value: 'no_marketing', label: 'No marketing messages' },
		{ value: 'do_not_disturb', label: 'Do not disturb' }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<form
	class="client-details-form"
	aria-label="Client details"
	onsubmit={(event) => {
		event.preventDefault();
		onSave($state.snapshot(draft));
	}}
>
	<div class="client-details-form__choices">
		<SegmentedControl
			label="Client type"
			value={draft.client_type}
			options={CLIENT_TYPE_OPTIONS}
			onchange={(next) => (draft.client_type = next as 'person' | 'company')}
		/>
		<SegmentedControl
			label="Status"
			value={draft.lifecycle_status}
			options={LIFECYCLE_OPTIONS}
			onchange={(next) => (draft.lifecycle_status = next as 'lead' | 'customer')}
		/>
	</div>

	<div class="client-details-form__grid">
		{#if isCompany}
			<div class="client-details-form__grid-full">
				<Input
					id="client-details-company"
					label="Company name"
					required
					bind:value={draft.company_name}
					invalid={Boolean(fieldErrors.company_name)}
					errorMessage={fieldErrors.company_name ?? ''}
					autocomplete="organization"
				/>
			</div>
			<Input
				id="client-details-first-name"
				label="Contact first name (optional)"
				bind:value={draft.first_name}
				invalid={Boolean(fieldErrors.first_name)}
				errorMessage={fieldErrors.first_name ?? ''}
				autocomplete="given-name"
			/>
			<Input
				id="client-details-last-name"
				label="Contact last name (optional)"
				bind:value={draft.last_name}
				invalid={Boolean(fieldErrors.last_name)}
				errorMessage={fieldErrors.last_name ?? ''}
				autocomplete="family-name"
			/>
		{:else}
			<Input
				id="client-details-first-name"
				label="First name"
				required
				bind:value={draft.first_name}
				invalid={Boolean(fieldErrors.first_name)}
				errorMessage={fieldErrors.first_name ?? ''}
				autocomplete="given-name"
			/>
			<Input
				id="client-details-last-name"
				label="Last name"
				required
				bind:value={draft.last_name}
				invalid={Boolean(fieldErrors.last_name)}
				errorMessage={fieldErrors.last_name ?? ''}
				autocomplete="family-name"
			/>
		{/if}

		<Input
			id="client-details-email"
			label="Email address"
			type="email"
			bind:value={draft.email}
			invalid={Boolean(fieldErrors.email)}
			errorMessage={fieldErrors.email ?? ''}
			autocomplete="email"
		/>
		<Input
			id="client-details-phone"
			label="Phone number"
			type="tel"
			bind:value={draft.phone}
			invalid={Boolean(fieldErrors.phone)}
			errorMessage={fieldErrors.phone ?? ''}
			autocomplete="tel"
		/>

		<div class="client-details-form__grid-full">
			<Input
				id="client-details-billing-email"
				label="Billing email (optional)"
				type="email"
				bind:value={draft.billing_email}
				invalid={Boolean(fieldErrors.billing_email)}
				errorMessage={fieldErrors.billing_email ?? ''}
				autocomplete="email"
			/>
			<p class="client-details-form__hint">Also send invoices and quotes here.</p>
		</div>

		{#if !isCompany}
			<div class="client-details-form__grid-full">
				<Input
					id="client-details-company"
					label="Company name (optional)"
					bind:value={draft.company_name}
					invalid={Boolean(fieldErrors.company_name)}
					errorMessage={fieldErrors.company_name ?? ''}
					autocomplete="organization"
				/>
			</div>
		{/if}

		<div class="client-details-form__policy client-details-form__grid-full">
			<label class="client-details-form__policy-label" for="client-details-policy">
				Communication setting
			</label>
			<div class="client-details-form__policy-row">
				<Select
					id="client-details-policy"
					value={draft.preferences.contact_policy}
					options={policyOptions}
					onchange={(value) =>
						(draft.preferences = {
							...draft.preferences,
							contact_policy: value as ClientPreferences['contact_policy']
						})}
				/>
				<button
					type="button"
					class="client-details-form__configure"
					onmouseenter={prefetchMessageStatus}
					onfocus={prefetchMessageStatus}
					onclick={() => (settingsOpen = true)}
				>
					<span aria-hidden="true">{@html settingsIcon}</span>Configure
				</button>
			</div>
		</div>
	</div>

	{#if error}
		<p class="client-details-form__error" role="alert">{error}</p>
	{/if}

	<div class="client-details-form__actions">
		<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
		<Button variant="primary" type="submit" loading={saving}>Save</Button>
	</div>
</form>

<CommunicationSettingsDialog
	open={settingsOpen}
	bind:preferences={draft.preferences}
	onClose={() => (settingsOpen = false)}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-details-form {
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

		&__hint {
			margin-top: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.client-details-form__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
