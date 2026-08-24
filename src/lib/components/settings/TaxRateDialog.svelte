<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import {
		createTaxRate,
		updateTaxRate,
		fetchTaxRatePropertyCount,
		type TaxRate,
		type TaxWriteError
	} from '$lib/settings/api';

	// Adds or edits one saved rate. Like PropertyDialog, this owns its own record and writes straight away —
	// nothing here goes near a page draft.
	let {
		open,
		rate = null,
		onSaved,
		onClose
	}: {
		open: boolean;
		/** The rate being edited, or null to add a new one. */
		rate?: TaxRate | null;
		onSaved: (rate: TaxRate) => void;
		onClose: () => void;
	} = $props();

	const isEdit = $derived(rate !== null);

	let draftName = $state(untrack(() => rate?.name ?? ''));
	let draftRate = $state(untrack(() => (rate ? (rate.rate_basis_points / 100).toString() : '')));
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	// Told once, when the dialog opens for an existing rate, so an edit explains its reach before Save.
	let propertyCount = $state<number | null>(null);
	let countLoading = $state(false);

	$effect(() => {
		const editing = rate;
		if (!editing) return;
		countLoading = true;
		fetchTaxRatePropertyCount(editing.id)
			.then((count) => (propertyCount = count))
			.catch(() => (propertyCount = null))
			.finally(() => (countLoading = false));
	});

	function close() {
		if (saving) return;
		onClose();
	}

	async function save() {
		const parsed = Number(draftRate);
		const name = draftName.trim();
		if (!name) {
			fieldErrors = { name: 'Give this tax rate a name.' };
			return;
		}
		if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100) {
			fieldErrors = { rate_basis_points: 'Enter a rate between 0 and 100.' };
			return;
		}

		saving = true;
		error = '';
		fieldErrors = {};
		const rateBasisPoints = Math.round(parsed * 100);
		try {
			const saved = rate
				? await updateTaxRate(rate.id, {
						expected_revision: rate.revision,
						name,
						rate_basis_points: rateBasisPoints
					})
				: await createTaxRate({ name, rate_basis_points: rateBasisPoints });
			onSaved(saved);
		} catch (cause) {
			const failure = cause as TaxWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			error = Object.keys(fieldErrors).length
				? ''
				: failure.reason === 'stale'
					? 'Someone else changed this tax rate. Close this, check the latest list, and try again.'
					: failure.message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title={isEdit ? 'Edit tax rate' : 'Add tax rate'} size="small" onClose={close}>
	<div class="tax-rate-dialog">
		{#if error}<p class="tax-rate-dialog__error" role="alert">{error}</p>{/if}

		<Input
			id="tax-rate-name"
			label="Name"
			placeholder="Sales tax"
			disabled={saving}
			bind:value={draftName}
			invalid={Boolean(fieldErrors.name)}
			errorMessage={fieldErrors.name ?? ''}
		/>

		<Input
			id="tax-rate-percent"
			label="Rate %"
			inputmode="decimal"
			disabled={saving}
			bind:value={draftRate}
			invalid={Boolean(fieldErrors.rate_basis_points)}
			errorMessage={fieldErrors.rate_basis_points ?? ''}
		/>

		{#if isEdit && !countLoading && propertyCount !== null && propertyCount > 0}
			<p class="tax-rate-dialog__note">
				{propertyCount}
				{propertyCount === 1 ? 'property is' : 'properties are'} pinned to this rate. This change only
				applies to future drafts — existing quotes and invoices keep what they already have.
			</p>
		{/if}

		<div class="tax-rate-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}
				>Cancel</Button
			>
			<Button variant="primary" loading={saving} onclick={() => void save()}>
				{isEdit ? 'Save' : 'Add rate'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.tax-rate-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
