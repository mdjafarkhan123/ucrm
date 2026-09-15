<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		setInvoiceDefaults,
		type InvoiceDefaults,
		type InvoicePaymentTerm
	} from '$lib/settings/api';

	// Changes both organization defaults together — the resolver picks residential or commercial by whether
	// the client is a company, so there is one dialog with two pickers rather than two separate destinations.
	let {
		open,
		current,
		terms,
		onSaved,
		onClose
	}: {
		open: boolean;
		current: InvoiceDefaults;
		terms: InvoicePaymentTerm[];
		onSaved: () => void;
		onClose: () => void;
	} = $props();

	let residentialChoice = $state(untrack(() => current.residential_term_id ?? ''));
	let commercialChoice = $state(untrack(() => current.commercial_term_id ?? ''));
	let saving = $state(false);
	let error = $state('');

	const options = $derived(terms.map((term) => ({ value: term.id, label: term.name })));

	function close() {
		if (saving) return;
		onClose();
	}

	async function save() {
		if (!residentialChoice || !commercialChoice) {
			error = 'Both the residential and commercial defaults need a payment term.';
			return;
		}
		saving = true;
		error = '';
		try {
			await setInvoiceDefaults({
				expected_revision: current.revision,
				residential_term_id: residentialChoice,
				commercial_term_id: commercialChoice
			});
			onSaved();
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Those defaults could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Change defaults" size="small" onClose={close}>
	<div class="invoice-defaults-dialog">
		{#if error}<p class="invoice-defaults-dialog__error" role="alert">{error}</p>{/if}

		<p class="invoice-defaults-dialog__hint">
			Commercial applies when the client's name is a company; everyone else uses residential. A
			client's own payment term, if they have one, always wins over either default.
		</p>

		<Select
			id="invoice-default-residential"
			label="Residential customers"
			bind:value={residentialChoice}
			{options}
			placeholder="Choose a payment term"
			disabled={saving}
		/>

		<Select
			id="invoice-default-commercial"
			label="Commercial customers"
			bind:value={commercialChoice}
			{options}
			placeholder="Choose a payment term"
			disabled={saving}
		/>

		<div class="invoice-defaults-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}
				>Cancel</Button
			>
			<Button variant="primary" loading={saving} onclick={() => void save()}>Save defaults</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.invoice-defaults-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
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
