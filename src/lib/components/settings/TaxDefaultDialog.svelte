<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		saveTaxDefault,
		isSaveConflict,
		fetchTaxDefaultPropertyCount,
		type TaxRate,
		type TaxDefault
	} from '$lib/settings/api';

	// Changes the Business default. Fetched only when this opens, and shown before Save rather than as a
	// second confirmation — how many Properties would follow the change for future documents, and that
	// existing documents never do.
	let {
		open,
		current,
		activeRates,
		onSaved,
		onClose
	}: {
		open: boolean;
		current: TaxDefault;
		activeRates: TaxRate[];
		onSaved: (result: {
			source: 'rate' | 'no_tax';
			rate_id: string | null;
			revision: number;
		}) => void;
		onClose: () => void;
	} = $props();

	function initialChoice() {
		if (current.source === 'rate' && current.rate_id) return `rate:${current.rate_id}`;
		if (current.source === 'no_tax') return 'no_tax';
		return '';
	}

	let choice = $state(untrack(initialChoice));
	let saving = $state(false);
	let error = $state('');

	let propertyCount = $state<number | null>(null);
	let countLoading = $state(true);

	$effect(() => {
		countLoading = true;
		fetchTaxDefaultPropertyCount()
			.then((count) => (propertyCount = count))
			.catch(() => (propertyCount = null))
			.finally(() => (countLoading = false));
	});

	const options = $derived([
		{ value: 'no_tax', label: 'No tax' },
		...activeRates.map((rate) => ({
			value: `rate:${rate.id}`,
			label: `${rate.name} (${(rate.rate_basis_points / 100).toFixed(2).replace(/\.?0+$/, '')}%)`
		}))
	]);

	function close() {
		if (saving) return;
		onClose();
	}

	async function save() {
		if (!choice) {
			error = 'Choose a saved rate or No tax.';
			return;
		}
		saving = true;
		error = '';
		const source = choice === 'no_tax' ? 'no_tax' : 'rate';
		const rateId = choice === 'no_tax' ? null : choice.slice('rate:'.length);
		try {
			const result = await saveTaxDefault({
				expected_revision: current.revision,
				source,
				rate_id: rateId
			});
			if (isSaveConflict(result)) {
				error = `${result.editor_name ?? 'Someone else'} just changed this. Refresh to see their version before saving yours.`;
				return;
			}
			onSaved({ source, rate_id: rateId, revision: result.tax_revision });
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'That could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Change Business default" size="small" onClose={close}>
	<div class="tax-default-dialog">
		{#if error}<p class="tax-default-dialog__error" role="alert">{error}</p>{/if}

		<div class="tax-default-dialog__field">
			<label class="tax-default-dialog__label" for="tax-default-choice">
				Applies to future documents whenever a Property doesn't pin its own rate
			</label>
			<Select
				id="tax-default-choice"
				bind:value={choice}
				{options}
				placeholder="Choose a saved rate or No tax"
				disabled={saving}
			/>
		</div>

		{#if !countLoading && propertyCount !== null && propertyCount > 0}
			<p class="tax-default-dialog__note">
				{propertyCount}
				{propertyCount === 1 ? 'property uses' : 'properties use'} the Business default and will follow
				this change for future documents. Documents already drafted or sent do not change.
			</p>
		{/if}

		<div class="tax-default-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}
				>Cancel</Button
			>
			<Button variant="primary" loading={saving} onclick={() => void save()}>Save default</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.tax-default-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
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
