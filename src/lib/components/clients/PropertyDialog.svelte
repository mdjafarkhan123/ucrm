<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		createProperty,
		deleteProperty,
		updateProperty,
		ClientWriteError,
		type ClientProperty,
		type ClientPropertyInput
	} from '$lib/clients/api';

	// Adds, edits, or removes one property. Unlike the blocks in the page body, this dialog owns a record of
	// its own, so its buttons are the save: it writes straight away and tells the page to refresh. Nothing
	// here goes near the page's draft or its action bar.
	let {
		open,
		clientId,
		property = null,
		onSaved,
		onClose
	}: {
		open: boolean;
		clientId: string;
		/** The property being edited, or null to add a new one. */
		property?: ClientProperty | null;
		onSaved: () => void;
		onClose: () => void;
	} = $props();

	type PropertyDraft = Required<Pick<ClientPropertyInput, 'address_line1' | 'city'>> &
		ClientPropertyInput;

	function draftFrom(source: ClientPropertyInput | null): PropertyDraft {
		return {
			label: source?.label ?? '',
			address_line1: source?.address_line1 ?? '',
			address_line2: source?.address_line2 ?? '',
			city: source?.city ?? '',
			state_region: source?.state_region ?? '',
			postal_code: source?.postal_code ?? '',
			country: source?.country ?? 'US',
			// Not shown here, but carried through so saving an address does not wipe notes set elsewhere.
			access_notes: source?.access_notes ?? ''
		};
	}

	// A one-time copy taken when the dialog mounts, so a background refetch cannot overwrite typing.
	let draft = $state<PropertyDraft>(untrack(() => draftFrom(property)));
	let saving = $state(false);
	let deleting = $state(false);
	let confirmingDelete = $state(false);
	let error = $state('');

	const isEdit = $derived(property !== null);
	const busy = $derived(saving || deleting);

	const COUNTRIES = [
		{ value: 'US', label: 'United States' },
		{ value: 'CA', label: 'Canada' },
		{ value: 'GB', label: 'United Kingdom' },
		{ value: 'AU', label: 'Australia' }
	];

	// The server needs a street and a city; everything else on a property is optional, including its name.
	const canSubmit = $derived(Boolean(draft.address_line1.trim() && draft.city.trim()));

	function messageFrom(thrown: unknown, fallback: string) {
		if (thrown instanceof ClientWriteError) {
			const firstField = Object.values(thrown.fieldErrors)[0];
			return firstField ?? thrown.message;
		}
		return thrown instanceof Error ? thrown.message : fallback;
	}

	async function save() {
		if (!canSubmit || busy) return;
		saving = true;
		error = '';
		try {
			const values = $state.snapshot(draft);
			if (property) await updateProperty(property.id, values);
			else await createProperty(clientId, values);
			onSaved();
		} catch (thrown) {
			error = messageFrom(thrown, 'That property could not be saved.');
		} finally {
			saving = false;
		}
	}

	async function remove() {
		if (!property || busy) return;
		deleting = true;
		error = '';
		try {
			await deleteProperty(property.id);
			onSaved();
		} catch (thrown) {
			error = messageFrom(thrown, 'That property could not be removed.');
			confirmingDelete = false;
		} finally {
			deleting = false;
		}
	}
</script>

<Dialog
	{open}
	title={isEdit ? 'Edit property' : 'Add property'}
	onClose={busy ? () => {} : onClose}
>
	<div class="property-dialog">
		<div class="property-dialog__grid">
			<div class="property-dialog__grid-full">
				<Input
					id="property-dialog-label"
					label="Property name (optional)"
					bind:value={draft.label}
					placeholder="Main site"
				/>
			</div>
			<div class="property-dialog__grid-full">
				<Input
					id="property-dialog-line1"
					label="Street address 1"
					required
					bind:value={draft.address_line1}
					autocomplete="address-line1"
				/>
			</div>
			<div class="property-dialog__grid-full">
				<Input
					id="property-dialog-line2"
					label="Street address 2 (optional)"
					bind:value={draft.address_line2}
					autocomplete="address-line2"
				/>
			</div>
			<Input
				id="property-dialog-city"
				label="City"
				required
				bind:value={draft.city}
				autocomplete="address-level2"
			/>
			<Input
				id="property-dialog-state"
				label="State or region"
				bind:value={draft.state_region}
				autocomplete="address-level1"
			/>
			<Input
				id="property-dialog-postal"
				label="Postal code"
				bind:value={draft.postal_code}
				autocomplete="postal-code"
			/>
			<div class="property-dialog__field">
				<label class="property-dialog__label" for="property-dialog-country">Country</label>
				<Select id="property-dialog-country" bind:value={draft.country} options={COUNTRIES} />
			</div>
		</div>

		{#if error}
			<p class="property-dialog__error" role="alert">{error}</p>
		{/if}

		{#if confirmingDelete}
			<!-- The confirmation replaces the footer rather than opening a second dialog on top of this one. -->
			<div class="property-dialog__confirm">
				<p class="property-dialog__confirm-text">
					Remove this property from the client? The address will no longer be available to pick.
				</p>
				<div class="property-dialog__actions">
					<Button
						variant="secondary"
						variation="subtle"
						disabled={busy}
						onclick={() => (confirmingDelete = false)}>Keep it</Button
					>
					<Button variation="destructive" loading={deleting} onclick={() => void remove()}>
						Remove property
					</Button>
				</div>
			</div>
		{:else}
			<div class="property-dialog__footer">
				{#if isEdit}
					<Button
						variant="tertiary"
						variation="destructive"
						disabled={busy}
						onclick={() => (confirmingDelete = true)}>Delete</Button
					>
				{/if}
				<div class="property-dialog__actions">
					<Button variant="secondary" variation="subtle" disabled={busy} onclick={onClose}>
						Cancel
					</Button>
					<Button
						variant="primary"
						disabled={!canSubmit}
						loading={saving}
						onclick={() => void save()}
					>
						{isEdit ? 'Save' : 'Add property'}
					</Button>
				</div>
			</div>
		{/if}
	</div>
</Dialog>

<style lang="scss">
	.property-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__grid {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__grid-full {
			grid-column: 1 / -1;
		}

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		// Delete sits opposite the pair that saves, so a destructive action is never next to the safe one.
		&__footer {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-left: auto;
		}

		&__confirm {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-critical);
			border-radius: var(--radius-base);
		}

		&__confirm-text {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}
	}

	@media (max-width: 767px) {
		.property-dialog__grid {
			grid-template-columns: 1fr;
		}

		.property-dialog__footer {
			flex-direction: column-reverse;
			align-items: stretch;
		}

		.property-dialog__actions {
			margin-left: 0;
		}
	}
</style>
