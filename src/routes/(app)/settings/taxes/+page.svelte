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
	import TaxRateDialog from '$lib/components/settings/TaxRateDialog.svelte';
	import TaxDefaultDialog from '$lib/components/settings/TaxDefaultDialog.svelte';
	import {
		fetchSettingsTaxes,
		settingsTaxesKey,
		setTaxRateActive,
		deleteTaxRate,
		fetchTaxRatePropertyCount,
		type TaxRate
	} from '$lib/settings/api';
	import receiptTaxIcon from '@tabler/icons/outline/receipt-tax.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsTaxesKey,
		queryFn: fetchSettingsTaxes
	}));

	let rateDialog = $state<{ rate: TaxRate | null } | null>(null);
	let defaultDialogOpen = $state(false);
	let deleteTarget = $state<{ rate: TaxRate; propertyCount: number } | null>(null);
	let deleteChecking = $state<string | null>(null);
	let deleting = $state(false);
	let toggling = $state<string | null>(null);

	function rateText(rateBasisPoints: number) {
		return `${(rateBasisPoints / 100).toFixed(2).replace(/\.?0+$/, '')}%`;
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: settingsTaxesKey });
	}

	function rateMenuItems(rate: TaxRate, defaultRateId: string | null) {
		const isDefault = defaultRateId === rate.id;
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => (rateDialog = { rate }) },
			rate.is_active
				? { label: 'Deactivate', icon: eyeOffIcon, onSelect: () => void toggleActive(rate, false) }
				: { label: 'Activate', icon: eyeIcon, onSelect: () => void toggleActive(rate, true) },
			{
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				disabled: isDefault,
				onSelect: () => void startDelete(rate)
			}
		];
	}

	async function toggleActive(rate: TaxRate, isActive: boolean) {
		toggling = rate.id;
		try {
			await setTaxRateActive(rate.id, { expected_revision: rate.revision, is_active: isActive });
			await invalidate();
			toast.success(isActive ? 'Tax rate activated.' : 'Tax rate deactivated.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That could not be changed.');
		} finally {
			toggling = null;
		}
	}

	async function startDelete(rate: TaxRate) {
		deleteChecking = rate.id;
		try {
			const count = await fetchTaxRatePropertyCount(rate.id);
			deleteTarget = { rate, propertyCount: count };
		} catch {
			toast.error('That could not be checked.');
		} finally {
			deleteChecking = null;
		}
	}

	async function confirmDelete() {
		if (!deleteTarget || deleteTarget.propertyCount > 0) return;
		deleting = true;
		try {
			await deleteTaxRate(deleteTarget.rate.id, { expected_revision: deleteTarget.rate.revision });
			deleteTarget = null;
			await invalidate();
			toast.success('Tax rate deleted.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That tax rate could not be deleted.');
		} finally {
			deleting = false;
		}
	}

	function rateSaved() {
		rateDialog = null;
		void invalidate();
		toast.success('Tax rate saved.');
	}

	function defaultSaved() {
		defaultDialogOpen = false;
		void invalidate();
		toast.success('Business default saved.');
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'rate', label: 'Rate', align: 'end' },
		{ key: 'status', label: 'Status' }
	];
</script>

<svelte:head><title>Taxes · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Taxes' }]}
	/>

	<PageHeader
		eyebrow="Business"
		title="Taxes"
		description="The rates your business charges, and which one applies by default."
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Taxes could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const taxes = query.data}
		{@const activeRates = taxes.rates.filter((rate) => rate.is_active)}

		<div class="taxes-page">
			<SectionBlock title="Saved tax rates" level={2}>
				{#snippet actions()}
					<Button size="small" onclick={() => (rateDialog = { rate: null })}>Add rate</Button>
				{/snippet}

				{#if taxes.rates.length === 0}
					<EmptyState
						icon={receiptTaxIcon}
						title="No tax rates yet"
						description="Add the rates your business charges so they're ready to use on quotes and invoices."
					>
						{#snippet action()}
							<Button variant="secondary" onclick={() => (rateDialog = { rate: null })}>
								Add tax rate
							</Button>
						{/snippet}
					</EmptyState>
				{:else}
					<DataTable
						{columns}
						items={taxes.rates}
						rowId={(rate) => rate.id}
						caption="Saved tax rates"
					>
						{#snippet row(rate: TaxRate)}
							<th scope="row">{rate.name}</th>
							<td class="taxes-page__rate">{rateText(rate.rate_basis_points)}</td>
							<td>
								<StatusBadge status={rate.is_active ? 'success' : 'inactive'}>
									{rate.is_active ? 'Active' : 'Inactive'}
								</StatusBadge>
							</td>
						{/snippet}
						{#snippet rowActions(rate: TaxRate)}
							<DropdownMenu
								triggerLabel={`Actions for ${rate.name}`}
								disabled={deleteChecking === rate.id || toggling === rate.id}
								items={rateMenuItems(
									rate,
									taxes.default.source === 'rate' ? taxes.default.rate_id : null
								)}
							/>
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>

			<SectionBlock
				title="Business default"
				hint="Used for any Property that doesn't pin its own rate."
				level={2}
			>
				{#snippet actions()}
					<Button size="small" variant="secondary" onclick={() => (defaultDialogOpen = true)}>
						{taxes.default.source === 'not_configured' ? 'Set default' : 'Change'}
					</Button>
				{/snippet}

				{#if taxes.default.source === 'not_configured'}
					<p class="taxes-page__default-value taxes-page__default-value--muted">
						Not configured — a priced Quote can't be published until this is set.
					</p>
				{:else if taxes.default.source === 'no_tax'}
					<p class="taxes-page__default-value">No tax</p>
				{:else}
					{@const rate = taxes.rates.find((entry) => entry.id === taxes.default.rate_id)}
					<p class="taxes-page__default-value">
						{rate ? `${rate.name} (${rateText(rate.rate_basis_points)})` : 'A saved rate'}
					</p>
				{/if}
			</SectionBlock>
		</div>

		{#if rateDialog}
			<TaxRateDialog
				open={true}
				rate={rateDialog.rate}
				onSaved={rateSaved}
				onClose={() => (rateDialog = null)}
			/>
		{/if}

		{#if defaultDialogOpen}
			<TaxDefaultDialog
				open={true}
				current={taxes.default}
				{activeRates}
				onSaved={defaultSaved}
				onClose={() => (defaultDialogOpen = false)}
			/>
		{/if}

		<ConfirmDialog
			open={deleteTarget !== null}
			title={deleteTarget && deleteTarget.propertyCount > 0
				? "This rate can't be deleted"
				: 'Delete this tax rate?'}
			tone={deleteTarget && deleteTarget.propertyCount > 0 ? 'default' : 'critical'}
			destructive={Boolean(deleteTarget && deleteTarget.propertyCount === 0)}
			confirmLabel="Delete rate"
			confirmDisabled={Boolean(deleteTarget && deleteTarget.propertyCount > 0)}
			cancelLabel={deleteTarget && deleteTarget.propertyCount > 0 ? 'Close' : 'Keep it'}
			loading={deleting}
			onConfirm={() => void confirmDelete()}
			onClose={() => (deleteTarget = null)}
		>
			{#if deleteTarget}
				{#if deleteTarget.propertyCount > 0}
					<p>
						{deleteTarget.propertyCount}
						{deleteTarget.propertyCount === 1 ? 'property uses' : 'properties use'}
						"{deleteTarget.rate.name}". Reassign
						{deleteTarget.propertyCount === 1 ? 'it' : 'them'} to another rate first, or deactivate this
						rate instead to stop new selections without unpinning anyone.
					</p>
				{:else}
					<p>
						This can't be undone. Existing quotes and invoices that already used this rate keep what
						they already have.
					</p>
				{/if}
			{/if}
		</ConfirmDialog>
	{/if}
</PageContainer>

<style lang="scss">
	.taxes-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__rate {
			font-variant-numeric: tabular-nums;
		}

		&__default-value {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;

			&--muted {
				color: var(--color-warning--onSurface);
				font-weight: 400;
			}
		}
	}
</style>
