<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import RecordFilesCard from '$lib/components/files/RecordFilesCard.svelte';
	import {
		createProperty,
		deleteProperty,
		fetchPropertyDeleteImpact,
		propertyDeleteImpactKey,
		updateProperty,
		ClientWriteError,
		type ClientProperty,
		type ClientPropertyInput
	} from '$lib/clients/api';
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	// Adds, edits, or removes one property. Unlike the blocks in the page body, this dialog owns a record of
	// its own, so its buttons are the save: it writes straight away and tells the page to refresh. Nothing
	// here goes near the page's draft or its action bar.
	let {
		open,
		clientId,
		clientLabel,
		property = null,
		onSaved,
		onClose
	}: {
		open: boolean;
		clientId: string;
		/** The owning client's display name, for the file picker's "On <client>" section. */
		clientLabel: string;
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
			access_notes: source?.access_notes ?? '',
			tax_rate_id: source?.tax_rate_id ?? null
		};
	}

	// A one-time copy taken when the dialog mounts, so a background refetch cannot overwrite typing.
	const toast = getToastManager();
	const queryClient = useQueryClient();

	let draft = $state<PropertyDraft>(untrack(() => draftFrom(property)));
	let saving = $state(false);
	let deleting = $state(false);
	let confirmingDelete = $state(false);
	let error = $state('');

	const isEdit = $derived(property !== null);
	const busy = $derived(saving || deleting);

	// Business default only — a property has nothing of its own to fall back to besides that, and it can
	// never inherit from itself. `enabled: open` keeps this off until the dialog is actually showing, in
	// case a session ever mounts it without the trigger's hover having warmed the cache first.
	const taxPickerQuery = createQuery(() => ({
		queryKey: taxPickerKey(),
		queryFn: () => fetchTaxPicker(),
		enabled: open,
		staleTime: 30_000,
		gcTime: 60_000
	}));

	const businessDefaultLabel = $derived.by(() => {
		const resolved = taxPickerQuery.data?.business_default;
		if (!resolved) return '…';
		if (resolved.rate_basis_points > 0)
			return `${resolved.name} — ${(resolved.rate_basis_points / 100).toFixed(2).replace(/\.?0+$/, '')}%`;
		return resolved.source === 'not_configured' ? 'not set yet' : 'No tax';
	});

	const taxOptions = $derived([
		{ value: '', label: `Inherit business default (${businessDefaultLabel})` },
		...(taxPickerQuery.data?.rates ?? []).map((rate) => ({
			value: rate.id,
			label: `${rate.name} — ${(rate.rate_basis_points / 100).toFixed(2).replace(/\.?0+$/, '')}%`
		}))
	]);

	// What a delete would take with it. Revealed only by the confirmation, so it stays off until then and the
	// Delete button's hover warms it; the delete itself re-checks all of this, so a stale answer cannot let
	// anything through.
	const impactQuery = createQuery(() => ({
		queryKey: propertyDeleteImpactKey(property?.id ?? ''),
		queryFn: () => fetchPropertyDeleteImpact(property!.id),
		enabled: Boolean(property) && confirmingDelete,
		staleTime: 15_000,
		gcTime: 60_000
	}));

	function warmImpact() {
		if (!property) return;
		void queryClient.prefetchQuery({
			queryKey: propertyDeleteImpactKey(property.id),
			queryFn: () => fetchPropertyDeleteImpact(property.id),
			staleTime: 15_000
		});
	}

	// "2 requests, 1 quote and 3 jobs" — only the kinds that are actually there.
	function workSummary(counts: { requests: number; quotes: number; jobs: number }) {
		const parts = [
			[counts.requests, 'request'],
			[counts.quotes, 'quote'],
			[counts.jobs, 'job']
		]
			.filter(([count]) => Number(count) > 0)
			.map(([count, noun]) => `${count} ${noun}${count === 1 ? '' : 's'}`);
		if (parts.length <= 1) return parts[0] ?? '';
		return `${parts.slice(0, -1).join(', ')} and ${parts.at(-1)}`;
	}

	const impact = $derived(impactQuery.data);

	// On a phone the confirmation opens below the fold and grows once the impact arrives, so it is brought
	// into view again when it does. Reading `impact` here is what re-runs this.
	function revealConfirm(node: HTMLElement) {
		void impact;
		node.scrollIntoView({ block: 'end', behavior: 'smooth' });
	}
	const blocked = $derived((impact?.blockers.length ?? 0) > 0);
	const doomedWork = $derived(impact ? workSummary(impact) : '');

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
			toast.success(property ? 'Property saved' : 'Property added');
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
			toast.success('Property deleted');
			// The delete can reach requests, quotes, jobs, visits, the pipeline, files and notifications at
			// once, so every cached view is marked stale; only what is on screen refetches now.
			void queryClient.invalidateQueries();
			onSaved();
		} catch (thrown) {
			error = messageFrom(thrown, 'That property could not be deleted.');
			confirmingDelete = false;
			void queryClient.invalidateQueries({ queryKey: propertyDeleteImpactKey(property.id) });
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
			<CountryPicker id="property-dialog-country" label="Country" bind:value={draft.country} />
			<div class="property-dialog__field property-dialog__grid-full">
				<label class="property-dialog__label" for="property-dialog-tax">Tax</label>
				<Select
					id="property-dialog-tax"
					value={draft.tax_rate_id ?? ''}
					options={taxOptions}
					onchange={(next) => (draft.tax_rate_id = next || null)}
				/>
			</div>
		</div>

		{#if error}
			<p class="property-dialog__error" role="alert">{error}</p>
		{/if}

		{#if property}
			<RecordFilesCard
				entityType="property"
				entityId={property.id}
				recordLabel="this property"
				pickerLabel="On this property"
				{clientId}
				{clientLabel}
				surface="section"
			/>
		{:else}
			<p class="property-dialog__files-hint">Files can be added once this property is saved.</p>
		{/if}

		{#if confirmingDelete}
			<!-- The confirmation replaces the footer rather than opening a second dialog on top of this one. -->
			<div class="property-dialog__confirm" aria-live="polite" {@attach revealConfirm}>
				{#if impactQuery.isError}
					<p class="property-dialog__confirm-text">
						{impactQuery.error?.message ?? 'We could not check what this property holds.'}
					</p>
				{:else if !impact}
					<div class="property-dialog__confirm-loading" aria-label="Checking this property">
						<span class="skeleton skeleton--text"></span>
						<span class="skeleton skeleton--text-short"></span>
					</div>
				{:else if blocked}
					<p class="property-dialog__confirm-title">This property can’t be deleted</p>
					<ul class="property-dialog__blockers">
						{#each impact.blockers as blocker (blocker)}
							<li>{blocker}.</li>
						{/each}
					</ul>
					<p class="property-dialog__confirm-text">
						These are part of your customer’s paperwork or payments, so the address has to stay.
					</p>
				{:else if doomedWork}
					<p class="property-dialog__confirm-title">Delete this property and its work?</p>
					<p class="property-dialog__confirm-text">
						This also permanently deletes <strong>{doomedWork}</strong> at this address, along with everything
						attached to them — visits, notes and files. They won’t show in your reports any more. This
						can’t be undone.
					</p>
				{:else}
					<p class="property-dialog__confirm-title">Delete this property?</p>
					<p class="property-dialog__confirm-text">
						The address and its notes and files are removed for good. This can’t be undone.
					</p>
				{/if}
				<div class="property-dialog__actions">
					<Button
						variant="secondary"
						variation="subtle"
						disabled={busy}
						onclick={() => (confirmingDelete = false)}>Keep it</Button
					>
					{#if impact && !blocked}
						<Button variation="destructive" loading={deleting} onclick={() => void remove()}>
							Delete property
						</Button>
					{/if}
				</div>
			</div>
		{:else}
			<div class="property-dialog__footer">
				{#if isEdit}
					<Button
						variant="tertiary"
						variation="destructive"
						disabled={busy}
						onhover={warmImpact}
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

		&__files-hint {
			margin: 0;
			color: var(--color-text--secondary);
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

		&__confirm-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__confirm-loading {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__blockers {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding-left: var(--space-large);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}

		&__confirm-text {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}
	}

	@media (max-width: 767px) {
		// minmax(0, …) lets a field shrink below its content's natural width instead of pushing past the dialog.
		.property-dialog__grid {
			grid-template-columns: minmax(0, 1fr);
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
