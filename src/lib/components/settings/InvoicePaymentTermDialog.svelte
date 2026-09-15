<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		createInvoicePaymentTerm,
		updateInvoicePaymentTerm,
		type InvoicePaymentTerm,
		type InvoiceTermWriteError
	} from '$lib/settings/api';

	// Adds or edits one saved payment term. Like TaxRateDialog, this owns its own record and writes straight
	// away — nothing here goes near a page draft.
	let {
		open,
		term = null,
		currentRevision,
		onSaved,
		onClose
	}: {
		open: boolean;
		/** The term being edited, or null to add a new one. */
		term?: InvoicePaymentTerm | null;
		/** The organization's current invoice_settings_revision, so a create/edit names the right one. */
		currentRevision: number;
		onSaved: () => void;
		onClose: () => void;
	} = $props();

	const isEdit = $derived(term !== null);
	// A protected term (e.g. "Due on receipt") may be renamed but its timing rule is built in — the database
	// refuses a rule change on one, so the picker stays locked rather than letting a save fail after the fact.
	const ruleLocked = $derived(term?.is_protected ?? false);

	let draftName = $state(untrack(() => term?.name ?? ''));
	let draftRule = $state<InvoicePaymentTerm['rule']>(untrack(() => term?.rule ?? 'net_days'));
	let draftNetDays = $state(untrack(() => term?.net_days?.toString() ?? '30'));
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const ruleOptions = [
		{ value: 'on_receipt', label: 'Due on receipt' },
		{ value: 'net_days', label: 'Net (days after issue)' },
		{ value: 'month_end', label: 'End of month' },
		{ value: 'next_month_end', label: 'End of next month' }
	];

	function close() {
		if (saving) return;
		onClose();
	}

	async function save() {
		const name = draftName.trim();
		if (name.length < 2 || name.length > 60) {
			fieldErrors = { name: 'A payment term needs a name between 2 and 60 characters.' };
			return;
		}
		let netDays: number | null = null;
		if (draftRule === 'net_days') {
			const parsed = Number(draftNetDays);
			if (!Number.isInteger(parsed) || parsed < 1 || parsed > 365) {
				fieldErrors = { net_days: 'A net term needs a day count between 1 and 365.' };
				return;
			}
			netDays = parsed;
		}

		saving = true;
		error = '';
		fieldErrors = {};
		try {
			const body = { expected_revision: currentRevision, name, rule: draftRule, net_days: netDays };
			if (term) {
				await updateInvoicePaymentTerm(term.id, body);
			} else {
				await createInvoicePaymentTerm(body);
			}
			onSaved();
		} catch (cause) {
			const failure = cause as InvoiceTermWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			error = Object.keys(fieldErrors).length
				? ''
				: failure.reason === 'stale'
					? 'Someone else changed invoice settings. Close this, check the latest list, and try again.'
					: failure.message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	{open}
	title={isEdit ? 'Edit payment term' : 'Add payment term'}
	size="small"
	onClose={close}
>
	<div class="invoice-term-dialog">
		{#if error}<p class="invoice-term-dialog__error" role="alert">{error}</p>{/if}

		<Input
			id="invoice-term-name"
			label="Name"
			placeholder="Net 30"
			disabled={saving}
			bind:value={draftName}
			invalid={Boolean(fieldErrors.name)}
			errorMessage={fieldErrors.name ?? ''}
		/>

		<Select
			id="invoice-term-rule"
			label="How the due date is worked out"
			bind:value={draftRule}
			options={ruleOptions}
			disabled={saving || ruleLocked}
		/>
		{#if ruleLocked}
			<p class="invoice-term-dialog__note">This term's timing is built in. Rename it instead.</p>
		{/if}

		{#if draftRule === 'net_days'}
			<Input
				id="invoice-term-net-days"
				label="Days after issue"
				inputmode="numeric"
				disabled={saving}
				bind:value={draftNetDays}
				invalid={Boolean(fieldErrors.net_days)}
				errorMessage={fieldErrors.net_days ?? ''}
			/>
		{/if}

		<div class="invoice-term-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}
				>Cancel</Button
			>
			<Button variant="primary" loading={saving} onclick={() => void save()}>
				{isEdit ? 'Save' : 'Add term'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.invoice-term-dialog {
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
