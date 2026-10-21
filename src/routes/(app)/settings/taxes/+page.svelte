<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
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
	import badgeCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
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

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Taxes · Settings · Contractor CRM</title></svelte:head>

<SettingsPresentation
	title="Taxes"
	description="The rates your business charges, and which one applies by default."
	icon={receiptTaxIcon}
	iconTone="job"
>
	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Taxes could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const taxes = query.data}
		{@const activeRates = taxes.rates.filter((rate) => rate.is_active)}

		<div class="taxes-page">
			<section class="taxes-page__hero" aria-labelledby="business-tax-default">
				<div class="taxes-page__hero-copy">
					<div class="taxes-page__eyebrow">
						<span class="taxes-page__hero-icon" aria-hidden="true">{@html badgeCheckIcon}</span
						>Business default
					</div>
					<div class="taxes-page__hero-value">
						<h2 id="business-tax-default">
							{#if taxes.default.source === 'not_configured'}Not configured
							{:else if taxes.default.source === 'no_tax'}No tax
							{:else}{taxes.rates.find((rate) => rate.id === taxes.default.rate_id)?.name ??
									'A saved rate'}{/if}
						</h2>
						{#if taxes.default.source === 'rate'}
							{@const defaultRate = taxes.rates.find((rate) => rate.id === taxes.default.rate_id)}
							{#if defaultRate}<span class="taxes-page__hero-pill"
									>{rateText(defaultRate.rate_basis_points)}</span
								>{/if}
						{/if}
					</div>
					<p>
						{taxes.default.source === 'not_configured'
							? 'Set a business default before publishing a priced quote.'
							: "Used for any Property that doesn't pin its own rate."}
					</p>
				</div>
				<dl class="taxes-page__counts">
					<div>
						<dt>Saved rates</dt>
						<dd>{taxes.rates.length}</dd>
					</div>
					<div>
						<dt>Active</dt>
						<dd>{activeRates.length}</dd>
					</div>
					<div>
						<dt>Inactive</dt>
						<dd>{taxes.rates.length - activeRates.length}</dd>
					</div>
				</dl>
				<div class="taxes-page__hero-action">
					<Button size="small" variant="secondary" onclick={() => (defaultDialogOpen = true)}
						>{taxes.default.source === 'not_configured' ? 'Set default' : 'Change'}</Button
					>
				</div>
			</section>

			<SectionBlock tone="inactive" title="Saved tax rates" icon={receiptTaxIcon} level={2}>
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
						variant="card"
						{columns}
						items={taxes.rates}
						rowId={(rate) => rate.id}
						caption="Saved tax rates"
					>
						{#snippet row(rate: TaxRate)}
							<th scope="row"
								><span class="taxes-page__name"
									><IconTile
										icon={receiptTaxIcon}
										tone="job"
										size={32}
									/>{rate.name}{#if taxes.default.source === 'rate' && taxes.default.rate_id === rate.id}<span
											class="taxes-page__default-badge">Default</span
										>{/if}</span
								></th
							>
							<td class="taxes-page__rate">{rateText(rate.rate_basis_points)}</td>
							<td>
								<StatusBadge size="compact" status={rate.is_active ? 'success' : 'inactive'}>
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
</SettingsPresentation>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.taxes-page :global(.section-block__title) {
		margin: 0;
		text-align: left;
		justify-content: flex-start;
	}
	.taxes-page :global(.data-table) {
		margin: 0 -24px -24px;
		width: calc(100% + 48px);
		--data-table-min-width: 0px;
	}
	.taxes-page :global(.section-block:has(> .section-block__actions)) {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		align-content: start;
	}
	.taxes-page :global(.section-block > *) {
		grid-column: 1 / -1;
	}
	.taxes-page :global(.section-block > .section-block__title) {
		grid-column: 1;
		grid-row: 1;
		align-self: center;
		margin: 0;
		justify-self: start;
	}
	.taxes-page :global(.section-block > .section-block__actions) {
		position: static;
		transform: none;
		padding: 0;
		background: transparent;
		grid-column: 2;
		grid-row: 1;
		align-self: center;
	}

	.taxes-page {
		display: flex;
		flex-direction: column;
		gap: 20px;

		&__rate {
			font-variant-numeric: tabular-nums;
			text-align: right;
		}

		&__hero {
			position: relative;
			isolation: isolate;
			overflow: hidden;
			display: flex;
			align-items: center;
			gap: 32px;
			padding: 28px 32px;
			border-radius: var(--radius-base);
			background: var(--color-base-lightBlue--800);
			color: var(--color-white);
		}
		&__hero::before,
		&__hero::after {
			content: '';
			position: absolute;
			z-index: -1;
			width: 300px;
			height: 300px;
			right: -40px;
			top: -120px;
			border: 1px solid rgb(255 255 255 / 8%);
			border-radius: 50%;
			pointer-events: none;
		}
		&__hero::after {
			width: 420px;
			height: 420px;
			right: -100px;
			top: -180px;
		}
		&__hero-copy {
			flex: 1;
			min-width: 0;
			display: grid;
			gap: 14px;
			p {
				margin: 0;
				color: rgb(255 255 255 / 70%);
				font-size: var(--typography--fontSize-base);
			}
		}
		&__eyebrow {
			display: flex;
			align-items: center;
			gap: 12px;
			color: rgb(255 255 255 / 70%);
			text-transform: uppercase;
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
			letter-spacing: 1.2px;
		}
		&__hero-icon {
			display: grid;
			place-items: center;
			width: 40px;
			height: 40px;
			border-radius: var(--radius-base);
			color: var(--color-white);
			background: var(--color-interactive);
			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
		&__hero-value {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: 14px;
			h2 {
				margin: 0;
				color: inherit;
				font-size: var(--typography--fontSize-stat);
				font-weight: 800;
				overflow-wrap: anywhere;
			}
		}
		&__hero-pill {
			padding: 5px 10px;
			border: 1px solid rgb(255 255 255 / 15%);
			border-radius: 999px;
			background: rgb(255 255 255 / 10%);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
		&__counts {
			display: flex;
			gap: 10px;
			margin: 0;
			div {
				min-width: 92px;
				padding: 16px;
				border: 1px solid rgb(255 255 255 / 10%);
				border-radius: var(--radius-base);
				background: rgb(255 255 255 / 8%);
			}
			dt {
				color: rgb(255 255 255 / 70%);
				font-size: var(--typography--fontSize-small);
			}
			dd {
				margin: 6px 0 0;
				font-size: var(--typography--fontSize-largest);
				font-weight: 800;
			}
		}
		&__hero-action {
			flex: 0 0 auto;
		}
		&__name {
			display: flex;
			align-items: center;
			gap: 12px;
		}
		&__default-badge {
			padding: 3px 8px;
			border-radius: 999px;
			background: var(--color-base-lightBlue--800);
			color: var(--color-white);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}
	}
	@media (max-width: 1100px) {
		.taxes-page__hero {
			flex-wrap: wrap;
		}
		.taxes-page__hero-copy {
			flex-basis: 100%;
		}
	}
</style>
