<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		addLostReason,
		fetchLostReasons,
		lostReasonsKey,
		setLostReasonRetired,
		type LostReasonOption
	} from '$lib/pipeline/api';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import restoreIcon from '@tabler/icons/outline/restore.svg?raw';

	// Settings → Pipeline → Lost reasons. Each change saves on its own, straight away — it is not part of
	// the page's Save. Nothing is deleted or renamed: retiring a reason only stops it being offered, so a
	// record lost as "No response" keeps reading "No response" (Pipedrive and HubSpot keep it the same way).
	let { canEdit }: { canEdit: boolean } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const uid = $props.id();

	const reasonsQuery = createQuery(() => ({
		queryKey: lostReasonsKey,
		queryFn: fetchLostReasons,
		staleTime: 5 * 60_000
	}));
	// Offered reasons first, retired ones after them, each in the list's own order.
	const reasons = $derived([
		...(reasonsQuery.data ?? []).filter((reason) => reason.retired_at === null),
		...(reasonsQuery.data ?? []).filter((reason) => reason.retired_at !== null)
	]);
	const offeredCount = $derived(reasons.filter((reason) => reason.retired_at === null).length);

	let newLabel = $state('');
	let adding = $state(false);
	let addError = $state('');

	// The board's dialogs and Sales Outcomes read the same list.
	function refresh() {
		return queryClient.invalidateQueries({ queryKey: lostReasonsKey });
	}

	async function add() {
		const label = newLabel.trim();
		if (!label || adding) return;
		adding = true;
		addError = '';
		try {
			const added = await addLostReason(label);
			newLabel = '';
			toast.success(`“${added.label}” added.`);
			await refresh();
		} catch (error) {
			addError = error instanceof Error ? error.message : 'That reason could not be added.';
		} finally {
			adding = false;
		}
	}

	async function setRetired(reason: LostReasonOption, retired: boolean) {
		try {
			await setLostReasonRetired(reason.key, retired);
			toast.success(
				retired
					? `“${reason.label}” retired. Records that already have it keep it.`
					: `“${reason.label}” is offered again.`
			);
			await refresh();
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'That reason could not be changed.');
		}
	}

	function menuItems(reason: LostReasonOption) {
		return reason.retired_at === null
			? [{ label: 'Retire', icon: archiveIcon, onSelect: () => void setRetired(reason, true) }]
			: [
					{ label: 'Bring back', icon: restoreIcon, onSelect: () => void setRetired(reason, false) }
				];
	}

	const columns: DataTableColumn[] = [
		{ key: 'label', label: 'Reason' },
		{ key: 'status', label: '' }
	];
</script>

<div class="lost-reasons">
	{#if canEdit}
		<form
			class="lost-reasons__add"
			onsubmit={(event) => {
				event.preventDefault();
				void add();
			}}
		>
			<Input
				id={`${uid}-new`}
				label="New reason"
				maxlength={60}
				bind:value={newLabel}
				invalid={Boolean(addError)}
				errorMessage={addError}
			/>
			<Button type="submit" variant="secondary" loading={adding} disabled={!newLabel.trim()}>
				Add reason
			</Button>
		</form>
	{/if}

	{#if reasonsQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading lost reasons" rows={4} />
	{:else if reasonsQuery.isError}
		<ErrorState
			description="Lost reasons could not be loaded."
			retry={() => reasonsQuery.refetch()}
		/>
	{:else}
		{#snippet rowActions(reason: LostReasonOption)}
			<!-- "Other" is always offered, so there is nothing to do with it. -->
			{#if reason.key !== 'other'}
				<DropdownMenu triggerLabel={`Actions for ${reason.label}`} items={menuItems(reason)} />
			{/if}
		{/snippet}
		<DataTable
			{columns}
			items={reasons}
			rowId={(reason) => reason.key}
			caption="Lost reasons"
			rowActions={canEdit ? rowActions : undefined}
		>
			{#snippet row(reason: LostReasonOption)}
				<th scope="row" class:lost-reasons__retired={reason.retired_at !== null}>
					{reason.label}
				</th>
				<td>
					{#if reason.retired_at !== null}
						<StatusBadge status="inactive">Retired</StatusBadge>
					{:else if reason.key === 'other'}
						<StatusBadge status="informative">Always offered</StatusBadge>
					{/if}
				</td>
			{/snippet}
		</DataTable>
		<p class="lost-reasons__hint">
			{offeredCount} of 25 reasons offered. Choosing a reason is always optional, and “Other” asks for
			a short note. Retiring a reason stops it being offered, but every record that already has it keeps
			it. To change a reason’s wording, add the new one and retire the old one.
		</p>
	{/if}
</div>

<style lang="scss">
	.lost-reasons {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__add {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);

			:global(.input) {
				flex: 1;
				max-width: 24rem;
			}

			@media (max-width: 639px) {
				flex-direction: column;
				align-items: stretch;

				:global(.input) {
					max-width: none;
				}
			}
		}

		&__retired {
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
