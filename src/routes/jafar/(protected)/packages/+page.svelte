<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto, preloadData } from '$app/navigation';
	import { resolve } from '$app/paths';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import restoreIcon from '@tabler/icons/outline/archive-off.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import PackageCreateDialog from '$lib/components/jafar/packages/PackageCreateDialog.svelte';
	import PackageWebsiteReminder from '$lib/components/jafar/packages/PackageWebsiteReminder.svelte';
	import PackageOffersSection from '$lib/components/jafar/packages/PackageOffersSection.svelte';
	import { jafarPackageKey, jafarPackagesKey } from '$lib/jafar/query-keys';
	import {
		changePackage,
		deletePackageDraft,
		fetchPackageBuilder,
		fetchPackages,
		formatUsd,
		isListed,
		type CatalogAction,
		type PackageSummary
	} from '$lib/jafar/packages';

	// Package builder P6: every package Jafar has made, with its draft and published edition. P7 adds the
	// catalog order, public or private, archive and restore, and the marketing-site reminders.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const packagesQuery = createQuery(() => ({
		queryKey: jafarPackagesKey,
		queryFn: fetchPackages,
		staleTime: 30_000
	}));
	const packages = $derived(packagesQuery.data ?? []);
	const currentPackages = $derived(packages.filter((pkg) => !pkg.archived_at));
	const archived = $derived(packages.filter((pkg) => pkg.archived_at));
	const reminders = $derived(packages.filter((pkg) => pkg.website_update_pending_since));

	let createOpen = $state(false);
	let copyFrom = $state<PackageSummary | null>(null);
	let deleteTarget = $state<PackageSummary | null>(null);
	let archiveTarget = $state<PackageSummary | null>(null);

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Package' },
		{ key: 'status', label: 'Status' },
		{ key: 'monthly', label: 'Monthly', align: 'end' },
		{ key: 'yearly', label: 'Yearly', align: 'end' },
		{ key: 'customers', label: 'Customers', align: 'end' }
	];

	function packageHref(pkg: PackageSummary) {
		return resolve(`/jafar/packages/${pkg.id}`);
	}

	function current(pkg: PackageSummary) {
		return pkg.draft ?? pkg.published;
	}

	function prefetch(pkg: PackageSummary) {
		void preloadData(packageHref(pkg));
		void queryClient.prefetchQuery({
			queryKey: jafarPackageKey(pkg.id),
			queryFn: () => fetchPackageBuilder(pkg.id),
			staleTime: 30_000
		});
	}

	function startCopy(pkg: PackageSummary) {
		copyFrom = pkg;
		createOpen = true;
	}

	function startCreate() {
		copyFrom = null;
		createOpen = true;
	}

	async function created(packageId: string) {
		createOpen = false;
		await queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
		toast.success('Draft created.');
		await goto(resolve(`/jafar/packages/${packageId}`));
	}

	function menuItems(pkg: PackageSummary, list: PackageSummary[]) {
		const index = list.indexOf(pkg);
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => goto(packageHref(pkg)) },
			{ label: 'Copy', icon: copyIcon, onSelect: () => startCopy(pkg) },
			...(index > 0
				? [
						{
							label: 'Move up',
							icon: arrowUpIcon,
							onSelect: () => change.mutate({ pkg, command: { action: 'move', direction: 'up' } })
						}
					]
				: []),
			...(index < list.length - 1
				? [
						{
							label: 'Move down',
							icon: arrowDownIcon,
							onSelect: () => change.mutate({ pkg, command: { action: 'move', direction: 'down' } })
						}
					]
				: []),
			...(pkg.published && !pkg.archived_at
				? [
						{
							label: pkg.visibility === 'public' ? 'Make private' : 'Make public',
							icon: pkg.visibility === 'public' ? eyeOffIcon : eyeIcon,
							onSelect: () =>
								change.mutate({
									pkg,
									command: {
										action: 'set_visibility',
										visibility: pkg.visibility === 'public' ? 'private' : 'public'
									}
								})
						},
						{ label: 'Archive', icon: archiveIcon, onSelect: () => (archiveTarget = pkg) }
					]
				: []),
			...(pkg.archived_at
				? [
						{
							label: 'Restore',
							icon: restoreIcon,
							onSelect: () => change.mutate({ pkg, command: { action: 'restore' } })
						}
					]
				: []),
			...(pkg.draft
				? [
						{
							label: pkg.published ? 'Discard draft' : 'Delete draft',
							icon: trashIcon,
							destructive: true,
							onSelect: () => (deleteTarget = pkg)
						}
					]
				: [])
		];
	}

	const successMessages: Record<CatalogAction['action'], string> = {
		set_visibility: 'Visibility changed.',
		move: 'Order changed.',
		archive: 'Package archived.',
		restore: 'Package restored.',
		confirm_website: 'Marked the marketing site as up to date.'
	};

	const change = createMutation(() => ({
		mutationFn: ({ pkg, command }: { pkg: PackageSummary; command: CatalogAction }) =>
			changePackage(pkg.id, command),
		onSuccess: (result, { command }) => {
			archiveTarget = null;
			if (result.applied || command.action === 'confirm_website') {
				toast.success(successMessages[command.action]);
			}
		},
		onError: (error) => {
			archiveTarget = null;
			toast.error(error.message);
		},
		onSettled: async (_result, _error, { pkg }) => {
			await queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
			await queryClient.invalidateQueries({ queryKey: jafarPackageKey(pkg.id) });
		}
	}));

	const remove = createMutation(() => ({
		mutationFn: (pkg: PackageSummary) =>
			deletePackageDraft(pkg.id, {
				edition_id: pkg.draft!.edition_id,
				revision: pkg.draft!.revision
			}),
		onSuccess: async (result, pkg) => {
			deleteTarget = null;
			toast.success(result.package_removed ? 'Package deleted.' : 'Draft discarded.');
			queryClient.removeQueries({ queryKey: jafarPackageKey(pkg.id) });
			await queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
		},
		onError: async (error) => {
			toast.error(error.message);
			await queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
		}
	}));
</script>

<svelte:head><title>Packages · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="packages-page">
	<PageHeader
		eyebrow="Platform owner"
		title="Packages"
		description="What contractors can buy: the app features, allowances, services, and prices in each offer."
	>
		{#snippet actions()}
			<Button onclick={startCreate}
				><span class="packages-page__button-icon" aria-hidden="true">{@html plusIcon}</span>New
				package</Button
			>
		{/snippet}
	</PageHeader>

	{#if packagesQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading packages" />
	{:else if packagesQuery.isError}
		<ErrorState
			title="Packages could not be loaded"
			description={packagesQuery.error.message}
			retry={() => packagesQuery.refetch()}
		/>
	{:else if packages.length === 0}
		<EmptyState
			title="No packages yet"
			description="Create a draft, choose what it includes, and set its prices."
			icon={packageIcon}
		>
			{#snippet action()}<Button onclick={startCreate}>New package</Button>{/snippet}
		</EmptyState>
	{:else}
		{#if reminders.length}
			<div class="packages-page__reminders">
				{#each reminders as pkg (pkg.id)}
					<PackageWebsiteReminder
						name={current(pkg)?.name ?? pkg.slug}
						changes={pkg.website_changes}
						pending={change.isPending &&
							change.variables?.pkg.id === pkg.id &&
							change.variables.command.action === 'confirm_website'}
						onConfirm={() =>
							change.mutate({
								pkg,
								command: {
									action: 'confirm_website',
									pending_since: pkg.website_update_pending_since!
								}
							})}
					/>
				{/each}
			</div>
		{/if}

		{#if currentPackages.length}
			{@render packageTable(currentPackages, 'Packages')}
		{:else}
			<EmptyState
				title="Every package is archived"
				description="Restore one below, or create a new package."
				icon={packageIcon}
			/>
		{/if}

		{#if archived.length}
			<section class="packages-page__archived" aria-labelledby="archived-packages-heading">
				<h2 id="archived-packages-heading" class="packages-page__section-title">Archived</h2>
				<p class="packages-page__section-hint">
					New customers cannot choose these. Customers already on them keep their edition.
				</p>
				{@render packageTable(archived, 'Archived packages')}
			</section>
		{/if}

		<PackageOffersSection {packages} />
	{/if}
</main>

{#snippet packageTable(list: PackageSummary[], caption: string)}
	<DataTable
		{columns}
		items={list}
		rowId={(pkg) => pkg.id}
		{caption}
		onRowHover={prefetch}
		onRowActivate={(pkg) => goto(packageHref(pkg))}
	>
		{#snippet row(pkg: PackageSummary)}
			<th scope="row">
				<a class="packages-page__name" href={packageHref(pkg)}>{current(pkg)?.name}</a>
				<span class="packages-page__slug">/{pkg.slug}</span>
			</th>
			<td>
				<div class="packages-page__badges">
					{#if pkg.published}
						<Badge status="success" size="small">Edition {pkg.published.edition_number}</Badge>
					{/if}
					{#if pkg.draft}
						<Badge status={pkg.published ? 'warning' : 'inactive'} size="small"
							>{pkg.published ? 'Unpublished changes' : 'Draft'}</Badge
						>
					{/if}
					{#if pkg.archived_at}
						<Badge size="small">Archived</Badge>
					{:else if isListed(pkg)}
						<Badge status="informative" size="small">Public</Badge>
					{:else if pkg.published}
						<Badge status="inactive" size="small">Private</Badge>
					{/if}
				</div>
			</td>
			<td class="packages-page__number align-end"
				>{formatUsd(current(pkg)?.monthly_price_usd_cents ?? null)}</td
			>
			<td class="packages-page__number align-end"
				>{formatUsd(current(pkg)?.yearly_price_usd_cents ?? null)}</td
			>
			<td class="packages-page__number align-end">{pkg.organization_count}</td>
		{/snippet}
		{#snippet rowActions(pkg: PackageSummary)}
			<DropdownMenu
				items={menuItems(pkg, list)}
				triggerLabel={`Actions for ${current(pkg)?.name}`}
			/>
		{/snippet}
	</DataTable>
{/snippet}

{#if createOpen}
	<PackageCreateDialog
		open={createOpen}
		{copyFrom}
		onClose={() => (createOpen = false)}
		onCreated={created}
	/>
{/if}

<ConfirmDialog
	open={archiveTarget !== null}
	title="Archive this package?"
	icon={archiveIcon}
	confirmLabel="Archive package"
	loading={change.isPending && change.variables?.command.action === 'archive'}
	onConfirm={() =>
		archiveTarget && change.mutate({ pkg: archiveTarget, command: { action: 'archive' } })}
	onClose={() => (archiveTarget = null)}
>
	<p>
		New customers can no longer choose “{archiveTarget ? current(archiveTarget)?.name : ''}”. {archiveTarget?.organization_count
			? `The ${archiveTarget.organization_count} ${archiveTarget.organization_count === 1 ? 'customer' : 'customers'} already on it keep their edition, price, and access.`
			: 'Nobody is on it today.'} You can restore it at any time.
	</p>
</ConfirmDialog>

<ConfirmDialog
	open={deleteTarget !== null}
	title={deleteTarget?.published ? 'Discard draft?' : 'Delete draft?'}
	icon={trashIcon}
	tone="critical"
	destructive
	confirmLabel={deleteTarget?.published ? 'Discard draft' : 'Delete draft'}
	loading={remove.isPending}
	onConfirm={() => deleteTarget && remove.mutate(deleteTarget)}
	onClose={() => (deleteTarget = null)}
>
	{#if deleteTarget?.published}
		<p>
			The changes in this draft are thrown away. Edition {deleteTarget.published.edition_number} stays
			as it is, and its {deleteTarget.organization_count}
			{deleteTarget.organization_count === 1 ? 'customer keeps' : 'customers keep'} their terms.
		</p>
	{:else}
		<p>
			“{deleteTarget?.draft?.name}” was never published, so nobody uses it. The draft and its web
			address are removed for good.
		</p>
	{/if}
</ConfirmDialog>

<style lang="scss">
	.packages-page {
		display: flex;
		flex-direction: column;

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
			color: var(--color-heading);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}

		&__slug {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}

		&__reminders {
			display: grid;
			gap: var(--space-small);
			margin-bottom: var(--space-base);
		}

		&__archived {
			display: grid;
			gap: var(--space-small);
			margin-top: var(--space-large);
		}

		&__section-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__section-hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__badges {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
		}

		&__number {
			font-variant-numeric: tabular-nums;
		}
	}
</style>
