<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import restoreIcon from '@tabler/icons/outline/archive-off.svg?raw';
	import discountIcon from '@tabler/icons/outline/discount.svg?raw';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import PackageOfferDialog from '$lib/components/jafar/packages/PackageOfferDialog.svelte';
	import { jafarPackageOffersKey } from '$lib/jafar/query-keys';
	import type { PackageSummary } from '$lib/jafar/packages';
	import {
		describeOfferTerms,
		eligibilityLabels,
		fetchPackageOffers,
		offerStatusLabels,
		setPackageOfferArchived,
		type OfferStatus,
		type PackageOffer
	} from '$lib/jafar/package-offers';

	// Package builder P11b: Jafar's introductory offers under his packages, the way Stripe keeps coupons
	// beside products. Each row says what the offer takes off, where it applies, and how many have claimed it.
	let { packages }: { packages: PackageSummary[] } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const offersQuery = createQuery(() => ({
		queryKey: jafarPackageOffersKey,
		queryFn: fetchPackageOffers,
		staleTime: 30_000
	}));
	const offers = $derived(offersQuery.data ?? []);

	let editing = $state<PackageOffer | null>(null);
	let dialogOpen = $state(false);
	let archiveTarget = $state<PackageOffer | null>(null);

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Offer' },
		{ key: 'terms', label: 'Discount' },
		{ key: 'packages', label: 'Packages' },
		{ key: 'status', label: 'Status' },
		{ key: 'claims', label: 'Claimed', align: 'end' }
	];

	const statusTone: Record<OfferStatus, 'success' | 'warning' | 'inactive' | 'informative'> = {
		open: 'success',
		scheduled: 'informative',
		ended: 'inactive',
		full: 'warning',
		archived: 'inactive'
	};

	function packageNames(offer: PackageOffer) {
		return (
			offer.package_ids
				.map((id) => {
					const pkg = packages.find((candidate) => candidate.id === id);
					return pkg ? ((pkg.published ?? pkg.draft)?.name ?? pkg.slug) : null;
				})
				.filter(Boolean)
				.join(', ') || '—'
		);
	}

	function formatDay(iso: string) {
		return new Date(iso).toLocaleDateString('en-US', {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	function openNew() {
		editing = null;
		dialogOpen = true;
	}

	function openEdit(offer: PackageOffer) {
		editing = offer;
		dialogOpen = true;
	}

	async function saved(created: boolean) {
		dialogOpen = false;
		toast.success(created ? 'Offer created.' : 'Offer saved.');
		await invalidateOffers();
	}

	// Offers change the public cards and every change-package preview, so all of them refetch.
	async function invalidateOffers() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: jafarPackageOffersKey }),
			queryClient.invalidateQueries({
				predicate: (query) => query.queryKey.includes('package-change-preview')
			})
		]);
	}

	const archive = createMutation(() => ({
		mutationFn: ({ offer, archived }: { offer: PackageOffer; archived: boolean }) =>
			setPackageOfferArchived(offer.id, archived),
		onSuccess: (_result, { archived }) => {
			archiveTarget = null;
			toast.success(archived ? 'Offer archived.' : 'Offer restored.');
		},
		onError: (error) => {
			archiveTarget = null;
			toast.error(error.message);
		},
		onSettled: invalidateOffers
	}));

	function menuItems(offer: PackageOffer) {
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => openEdit(offer) },
			offer.archived_at
				? {
						label: 'Restore',
						icon: restoreIcon,
						onSelect: () => archive.mutate({ offer, archived: false })
					}
				: { label: 'Archive', icon: archiveIcon, onSelect: () => (archiveTarget = offer) }
		];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="package-offers" aria-labelledby="package-offers-heading">
	<div class="package-offers__header">
		<div>
			<h2 id="package-offers-heading" class="package-offers__title">Introductory offers</h2>
			<p class="package-offers__hint">
				A discount for a customer's first months or first year. After that they pay the package's
				normal price.
			</p>
		</div>
		<Button variant="secondary" onclick={openNew}
			><span class="package-offers__button-icon" aria-hidden="true">{@html plusIcon}</span>New offer</Button
		>
	</div>

	{#if offersQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading offers" />
	{:else if offersQuery.isError}
		<ErrorState
			title="Offers could not be loaded"
			description={offersQuery.error.message}
			retry={() => offersQuery.refetch()}
		/>
	{:else if offers.length === 0}
		<EmptyState
			title="No offers yet"
			description="For example, 50% off the first 3 months for new customers."
			icon={discountIcon}
		>
			{#snippet action()}<Button onclick={openNew}>New offer</Button>{/snippet}
		</EmptyState>
	{:else}
		<DataTable
			{columns}
			items={offers}
			rowId={(offer) => offer.id}
			caption="Introductory offers"
			onRowActivate={openEdit}
		>
			{#snippet row(offer: PackageOffer)}
				<th scope="row">
					<button type="button" class="package-offers__name" onclick={() => openEdit(offer)}
						>{offer.name}</button
					>
					<span class="package-offers__meta">
						{offer.apply_mode === 'code' ? `Code ${offer.code}` : 'Automatic'} · {eligibilityLabels[
							offer.customer_eligibility
						]}
					</span>
				</th>
				<td>{describeOfferTerms(offer)}</td>
				<td>{packageNames(offer)}</td>
				<td>
					<Badge status={statusTone[offer.status]} size="small"
						>{offerStatusLabels[offer.status]}</Badge
					>
					<span class="package-offers__meta">
						{offer.status === 'scheduled'
							? `Opens ${formatDay(offer.claim_starts_at)}`
							: offer.claim_ends_at
								? `${offer.status === 'ended' ? 'Closed' : 'Until'} ${formatDay(offer.claim_ends_at)}`
								: 'No end date'}
					</span>
				</td>
				<td class="package-offers__number align-end">
					{offer.claim_count}{offer.redemption_cap ? ` of ${offer.redemption_cap}` : ''}
				</td>
			{/snippet}
			{#snippet rowActions(offer: PackageOffer)}
				<DropdownMenu items={menuItems(offer)} triggerLabel={`Actions for ${offer.name}`} />
			{/snippet}
		</DataTable>
	{/if}
</section>

{#if dialogOpen}
	<PackageOfferDialog
		offer={editing}
		{packages}
		onClose={() => (dialogOpen = false)}
		onSaved={saved}
	/>
{/if}

<ConfirmDialog
	open={archiveTarget !== null}
	title="Archive this offer?"
	icon={archiveIcon}
	confirmLabel="Archive offer"
	loading={archive.isPending}
	onConfirm={() => archiveTarget && archive.mutate({ offer: archiveTarget, archived: true })}
	onClose={() => (archiveTarget = null)}
>
	<p>
		Nobody new can claim “{archiveTarget?.name}”. {archiveTarget?.claim_count
			? `The ${archiveTarget.claim_count} ${archiveTarget.claim_count === 1 ? 'customer' : 'customers'} who claimed it keep their discounted months.`
			: 'Nobody has claimed it yet.'} You can restore it at any time.
	</p>
</ConfirmDialog>

<style lang="scss">
	.package-offers {
		display: grid;
		gap: var(--space-small);
		margin-top: var(--space-largest);

		&__header {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__hint {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__button-icon {
			display: inline-flex;
			width: 1.8rem;
			height: 1.8rem;

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}

		&__name {
			display: block;
			padding: 0;
			border: 0;
			color: var(--color-heading);
			background: none;
			font: inherit;
			font-weight: 600;
			text-align: left;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__meta {
			display: block;
			margin-top: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}

		&__number {
			font-variant-numeric: tabular-nums;
		}
	}
</style>
