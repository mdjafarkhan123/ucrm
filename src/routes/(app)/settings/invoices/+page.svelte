<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
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

<PageContainer variant="fill">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Invoices' }]}
	/>

	<PageHeader
		eyebrow="Business"
		title="Invoice Settings"
		description="Your payment terms, and which one applies by default."
	/>

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
			<SectionBlock title="Payment terms" level={2}>
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
									<StatusBadge status="inactive">Built in</StatusBadge>
								{/if}
							</td>
						{/snippet}
						{#snippet rowActions(term: InvoicePaymentTerm)}
							<DropdownMenu triggerLabel={`Actions for ${term.name}`} items={termMenuItems(term)} />
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>

			<SectionBlock
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
						<span class="invoices-page__default-value">{residentialTerm?.name ?? 'Not set'}</span>
					</div>
					<div class="invoices-page__default">
						<span class="invoices-page__default-label">Commercial customers</span>
						<span class="invoices-page__default-value">{commercialTerm?.name ?? 'Not set'}</span>
					</div>
				</div>
			</SectionBlock>
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
</PageContainer>

<style lang="scss">
	.invoices-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__defaults {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-large);
		}

		&__default {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
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
</style>
