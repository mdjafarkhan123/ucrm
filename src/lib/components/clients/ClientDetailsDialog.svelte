<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import CommunicationSettingsDialog from './CommunicationSettingsDialog.svelte';
	import type { ClientIdentityDraft, ClientPreferences } from '$lib/clients/api';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';

	// Edits the client's own details without saving them. Done hands the new values back to the page,
	// which holds them as a draft until the page's action bar saves everything at once.
	let {
		open,
		values,
		wasCustomer = false,
		onDone,
		onClose
	}: {
		open: boolean;
		values: ClientIdentityDraft;
		wasCustomer?: boolean;
		onDone: (next: ClientIdentityDraft) => void;
		onClose: () => void;
	} = $props();

	// A one-time copy taken when the dialog mounts. The page mounts it fresh each time it opens, so every
	// visit starts from what the page holds, and a background refetch can never overwrite half-typed fields.
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
<Dialog {open} title="Client details" {onClose}>
	<div class="client-details-dialog">
		<div class="client-details-dialog__choices">
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

		<div class="client-details-dialog__grid">
			{#if isCompany}
				<div class="client-details-dialog__grid-full">
					<Input
						id="client-dialog-company"
						label="Company name"
						required
						bind:value={draft.company_name}
						autocomplete="organization"
					/>
				</div>
				<Input
					id="client-dialog-first-name"
					label="Contact first name (optional)"
					bind:value={draft.first_name}
					autocomplete="given-name"
				/>
				<Input
					id="client-dialog-last-name"
					label="Contact last name (optional)"
					bind:value={draft.last_name}
					autocomplete="family-name"
				/>
			{:else}
				<Input
					id="client-dialog-first-name"
					label="First name"
					required
					bind:value={draft.first_name}
					autocomplete="given-name"
				/>
				<Input
					id="client-dialog-last-name"
					label="Last name"
					required
					bind:value={draft.last_name}
					autocomplete="family-name"
				/>
			{/if}

			<Input
				id="client-dialog-email"
				label="Email address"
				type="email"
				bind:value={draft.email}
				autocomplete="email"
			/>
			<Input
				id="client-dialog-phone"
				label="Phone number"
				type="tel"
				bind:value={draft.phone}
				autocomplete="tel"
			/>

			{#if !isCompany}
				<div class="client-details-dialog__grid-full">
					<Input
						id="client-dialog-company"
						label="Company name (optional)"
						bind:value={draft.company_name}
						autocomplete="organization"
					/>
				</div>
			{/if}

			<div class="client-details-dialog__policy client-details-dialog__grid-full">
				<label class="client-details-dialog__policy-label" for="client-dialog-policy">
					Communication setting
				</label>
				<div class="client-details-dialog__policy-row">
					<Select
						id="client-dialog-policy"
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
						class="client-details-dialog__configure"
						onclick={() => (settingsOpen = true)}
					>
						<span aria-hidden="true">{@html settingsIcon}</span>Configure
					</button>
				</div>
			</div>
		</div>

		<div class="client-details-dialog__actions">
			<Button variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button variant="primary" onclick={() => onDone($state.snapshot(draft))}>Done</Button>
		</div>
	</div>
</Dialog>

<CommunicationSettingsDialog
	open={settingsOpen}
	bind:preferences={draft.preferences}
	onClose={() => (settingsOpen = false)}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-details-dialog {
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

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.client-details-dialog__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
