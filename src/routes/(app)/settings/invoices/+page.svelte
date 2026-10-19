<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import SettingsPresentation from '$lib/components/settings/SettingsPresentation.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import InvoicePaymentTermDialog from '$lib/components/settings/InvoicePaymentTermDialog.svelte';
	import InvoiceDefaultsDialog from '$lib/components/settings/InvoiceDefaultsDialog.svelte';
	import AccountingExportSection from '$lib/components/settings/AccountingExportSection.svelte';
	import {
		fetchSettingsInvoices,
		settingsInvoicesKey,
		removeInvoicePaymentTerm,
		type InvoicePaymentTerm
	} from '$lib/settings/api';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsInvoicesKey,
		queryFn: fetchSettingsInvoices
	}));

	let termDialog = $state<{ term: InvoicePaymentTerm | null } | null>(null);
	let defaultsDialogOpen = $state(false);
	let removeTarget = $state<InvoicePaymentTerm | null>(null);
	let removing = $state(false);

	function dueText(term: Pick<InvoicePaymentTerm, 'rule' | 'net_days'>) {
		switch (term.rule) {
			case 'on_receipt':
				return 'Due on receipt';
			case 'month_end':
				return 'End of month';
			case 'next_month_end':
				return 'End of next month';
			case 'net_days':
				return `Net ${term.net_days} days`;
		}
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: settingsInvoicesKey });
	}

	function termMenuItems(term: InvoicePaymentTerm) {
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => (termDialog = { term }) },
			{
				label: 'Remove',
				icon: trashIcon,
				destructive: true,
				disabled: term.is_protected,
				onSelect: () => (removeTarget = term)
			}
		];
	}

	function termSaved() {
		termDialog = null;
		void invalidate();
		toast.success('Payment term saved.');
	}

	function defaultsSaved() {
		defaultsDialogOpen = false;
		void invalidate();
		toast.success('Defaults saved.');
	}

	async function confirmRemove() {
		if (!removeTarget) return;
		const revision = query.data?.defaults.revision;
		if (revision === undefined) return;
		removing = true;
		try {
			await removeInvoicePaymentTerm(removeTarget.id, { expected_revision: revision });
			removeTarget = null;
			await invalidate();
			toast.success('Payment term removed.');
		} catch (cause) {
			toast.error(
				cause instanceof Error ? cause.message : 'That payment term could not be removed.'
			);
		} finally {
			removing = false;
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'due', label: 'Due' },
		{ key: 'status', label: '' }
	];
</script>

<svelte:head><title>Invoices · Settings · Contractor CRM</title></svelte:head>

<SettingsPresentation
	title="Invoice Settings"
	description="Your payment terms, and which one applies by default."
	icon={receiptIcon}
	iconTone="invoice"
>
	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Invoice settings could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const invoices = query.data}
		{@const residentialTerm = invoices.terms.find(
			(term) => term.id === invoices.defaults.residential_term_id
		)}
		{@const commercialTerm = invoices.terms.find(
			(term) => term.id === invoices.defaults.commercial_term_id
		)}

		<div class="invoices-page">
			<div class="invoices-page__grid">
				<SectionBlock tone="invoice" title="Payment terms" icon={receiptIcon} level={2}>
					{#snippet actions()}
						<Button size="small" onclick={() => (termDialog = { term: null })}>Add term</Button>
					{/snippet}

					{#if invoices.terms.length === 0}
						<EmptyState
							icon={receiptIcon}
							title="No payment terms yet"
							description="Add the payment terms your business offers so they're ready to use on invoices."
						>
							{#snippet action()}
								<Button variant="secondary" onclick={() => (termDialog = { term: null })}>
									Add payment term
								</Button>
							{/snippet}
						</EmptyState>
					{:else}
						<DataTable
							variant="card"
							{columns}
							items={invoices.terms}
							rowId={(term) => term.id}
							caption="Payment terms"
						>
							{#snippet row(term: InvoicePaymentTerm)}
								<th scope="row">{term.name}</th>
								<td>{dueText(term)}</td>
								<td>
									{#if term.is_protected}
										<StatusBadge status="inactive" size="compact">Built in</StatusBadge>
									{/if}
								</td>
							{/snippet}
							{#snippet rowActions(term: InvoicePaymentTerm)}
								<DropdownMenu
									triggerLabel={`Actions for ${term.name}`}
									items={termMenuItems(term)}
								/>
							{/snippet}
						</DataTable>
					{/if}
				</SectionBlock>

				<aside class="invoices-page__rail">
					<SectionBlock
						tone="invoice"
						icon={receiptIcon}
						title="Defaults"
						hint="Applied to a new invoice unless the client has their own payment term."
						level={2}
					>
						{#snippet actions()}
							<Button size="small" variant="secondary" onclick={() => (defaultsDialogOpen = true)}>
								Change
							</Button>
						{/snippet}

						<div class="invoices-page__defaults">
							<div class="invoices-page__default">
								<span class="invoices-page__default-label">Residential customers</span>
								<span class="invoices-page__default-value"
									>{residentialTerm?.name ?? 'Not set'}</span
								>
							</div>
							<div class="invoices-page__default">
								<span class="invoices-page__default-label">Commercial customers</span>
								<span class="invoices-page__default-value">{commercialTerm?.name ?? 'Not set'}</span
								>
							</div>
						</div>
					</SectionBlock>

					<SectionBlock
						tone="invoice"
						icon={receiptIcon}
						title="Opening balances"
						hint="Bring in what a client already owed you, or a credit they already had, from before you started using this CRM."
						level={2}
					>
						<Button
							variant="secondary"
							href={resolve('/(app)/settings/invoices/opening-balances/import')}
						>
							Import opening balances
						</Button>
					</SectionBlock>
				</aside>
			</div>
			<AccountingExportSection />
		</div>

		{#if termDialog}
			<InvoicePaymentTermDialog
				open={true}
				term={termDialog.term}
				currentRevision={invoices.defaults.revision}
				onSaved={termSaved}
				onClose={() => (termDialog = null)}
			/>
		{/if}

		{#if defaultsDialogOpen}
			<InvoiceDefaultsDialog
				open={true}
				current={invoices.defaults}
				terms={invoices.terms}
				onSaved={defaultsSaved}
				onClose={() => (defaultsDialogOpen = false)}
			/>
		{/if}

		<ConfirmDialog
			open={removeTarget !== null}
			title="Remove this payment term?"
			tone="critical"
			destructive
			confirmLabel="Remove term"
			loading={removing}
			onConfirm={() => void confirmRemove()}
			onClose={() => (removeTarget = null)}
		>
			<p>
				This can't be undone. Existing invoices that already used "{removeTarget?.name}" keep what
				they have. If it's currently a default, your business falls back to "Due on receipt".
			</p>
		</ConfirmDialog>
	{/if}
</SettingsPresentation>

<style lang="scss">
	.invoices-page :global(.section-block__title) {
		margin: 0;
		text-align: left;
		justify-content: flex-start;
	}
	.invoices-page :global(.data-table) {
		margin: 0 -24px -24px;
		width: calc(100% + 48px);
		--data-table-min-width: 0px;
	}
	.invoices-page :global(.section-block:has(> .section-block__actions)) {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		align-content: start;
	}
	.invoices-page :global(.section-block > *) {
		grid-column: 1 / -1;
	}
	.invoices-page :global(.section-block > .section-block__title) {
		grid-column: 1;
		grid-row: 1;
		align-self: center;
		margin: 0;
		justify-self: start;
	}
	.invoices-page :global(.section-block > .section-block__actions) {
		position: static;
		transform: none;
		padding: 0;
		background: transparent;
		grid-column: 2;
		grid-row: 1;
		align-self: center;
	}

	.invoices-page {
		display: flex;
		flex-direction: column;
		gap: 20px;

		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 360px;
			align-items: start;
			gap: 20px;
		}
		&__rail {
			display: flex;
			flex-direction: column;
			gap: 20px;
			min-width: 0;
		}
		&__defaults {
			display: grid;
			gap: var(--space-large);
		}

		&__default {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			padding: 14px 16px;
			background: var(--color-informative--surface);
			border-radius: var(--radius-base);
		}

		&__default-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__default-value {
			color: var(--color-heading);
			font-weight: 600;
		}
	}
	@media (max-width: 1100px) {
		.invoices-page__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
