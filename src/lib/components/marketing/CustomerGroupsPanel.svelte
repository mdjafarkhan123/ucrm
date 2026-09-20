<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CustomerGroupDialog from './CustomerGroupDialog.svelte';
	import {
		fetchCustomerGroups,
		marketingCustomerGroupsKey,
		archiveCustomerGroupRequest
	} from '$lib/marketing/api';
	import type { MarketingCustomerGroup } from '$lib/marketing/customer-groups';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const query = createQuery(() => ({
		queryKey: marketingCustomerGroupsKey,
		queryFn: fetchCustomerGroups
	}));

	let dialog = $state<{ group: MarketingCustomerGroup | null } | null>(null);
	let deleteTarget = $state<MarketingCustomerGroup | null>(null);
	let deleting = $state(false);

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: marketingCustomerGroupsKey });
	}

	function menuItems(group: MarketingCustomerGroup) {
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => (dialog = { group }) },
			{
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				onSelect: () => (deleteTarget = group)
			}
		];
	}

	function saved() {
		const wasCreate = dialog?.group === null;
		dialog = null;
		void invalidate();
		toast.success(wasCreate ? 'Customer group saved.' : 'Customer group updated.');
	}

	async function confirmDelete() {
		if (!deleteTarget) return;
		deleting = true;
		try {
			await archiveCustomerGroupRequest(deleteTarget.id);
			deleteTarget = null;
			await invalidate();
			toast.success('Customer group deleted.');
		} catch (cause) {
			toast.error(
				cause instanceof Error ? cause.message : 'That customer group could not be deleted.'
			);
		} finally {
			deleting = false;
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'description', label: 'Description' },
		{ key: 'updated_at', label: 'Last updated' }
	];

	const dateFormatter = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });
</script>

<SectionBlock
	title="Customer groups"
	hint="Saved recipient rules. Counts follow your customers and jobs."
	level={2}
>
	{#snippet actions()}
		<Button size="small" onclick={() => (dialog = { group: null })}>New group</Button>
	{/snippet}

	{#if query.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading customer groups" />
	{:else if query.isError}
		<ErrorState description="Customer groups could not be loaded." retry={() => query.refetch()} />
	{:else if query.data.length === 0}
		<EmptyState
			icon={usersGroupIcon}
			title="No customer groups yet"
			description="Save a rule set once and reuse it every time you email past customers."
		>
			{#snippet action()}
				<Button variant="secondary" onclick={() => (dialog = { group: null })}>New group</Button>
			{/snippet}
		</EmptyState>
	{:else}
		<DataTable {columns} items={query.data} rowId={(group) => group.id} caption="Customer groups">
			{#snippet row(group: MarketingCustomerGroup)}
				<th scope="row">{group.name}</th>
				<td>{group.description || '—'}</td>
				<td>{dateFormatter.format(new Date(group.updated_at))}</td>
			{/snippet}
			{#snippet rowActions(group: MarketingCustomerGroup)}
				<DropdownMenu triggerLabel={`Actions for ${group.name}`} items={menuItems(group)} />
			{/snippet}
		</DataTable>
	{/if}
</SectionBlock>

{#if dialog}
	<CustomerGroupDialog
		open={true}
		group={dialog.group}
		onSaved={saved}
		onClose={() => (dialog = null)}
	/>
{/if}

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this customer group?"
	tone="critical"
	destructive
	confirmLabel="Delete group"
	cancelLabel="Keep it"
	loading={deleting}
	onConfirm={() => void confirmDelete()}
	onClose={() => (deleteTarget = null)}
>
	<p>
		This can't be undone. Past campaigns that used "{deleteTarget?.name}" keep their own recipient
		history.
	</p>
</ConfirmDialog>
