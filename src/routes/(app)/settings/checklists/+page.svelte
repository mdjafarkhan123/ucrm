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
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ChecklistTemplateDialog from '$lib/components/settings/ChecklistTemplateDialog.svelte';
	import {
		checklistTemplatesKey,
		fetchChecklistTemplates,
		setChecklistTemplateArchived
	} from '$lib/checklists/api';
	import { CHECKLIST_ITEM_TYPE_LABELS, type ChecklistTemplate } from '$lib/checklists/types';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import archiveOffIcon from '@tabler/icons/outline/archive-off.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Archived checklists stay in the list behind a badge rather than disappearing: a job that used one
	// still names it, and the person who archived it by mistake needs a way back.
	const query = createQuery(() => ({
		queryKey: checklistTemplatesKey(true),
		queryFn: () => fetchChecklistTemplates(true)
	}));

	let dialog = $state<{ template: ChecklistTemplate | null } | null>(null);
	let archiving = $state<string | null>(null);

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: ['checklists'] });
	}

	async function toggleArchived(template: ChecklistTemplate) {
		archiving = template.id;
		try {
			await setChecklistTemplateArchived(template.id, !template.archived);
			await invalidate();
			toast.success(template.archived ? 'Checklist restored.' : 'Checklist archived.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That could not be changed.');
		} finally {
			archiving = null;
		}
	}

	function menuItems(template: ChecklistTemplate) {
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => (dialog = { template }) },
			template.archived
				? { label: 'Restore', icon: archiveOffIcon, onSelect: () => void toggleArchived(template) }
				: { label: 'Archive', icon: archiveIcon, onSelect: () => void toggleArchived(template) }
		];
	}

	function saved(result: { jobsAlreadyUsing: number }) {
		const editing = dialog?.template !== null;
		dialog = null;
		void invalidate();
		if (editing && result.jobsAlreadyUsing > 0) {
			toast.success(
				result.jobsAlreadyUsing === 1
					? 'Checklist saved. The 1 job already using it keeps the questions its crew has been answering.'
					: `Checklist saved. The ${result.jobsAlreadyUsing} jobs already using it keep the questions their crews have been answering.`
			);
		} else {
			toast.success('Checklist saved.');
		}
	}

	/** "3 questions · 1 must be answered" — enough to recognise a checklist without opening it. */
	function summary(template: ChecklistTemplate) {
		const required = template.items.filter((item) => item.required).length;
		const count = `${template.items.length} question${template.items.length === 1 ? '' : 's'}`;
		return required > 0 ? `${count} · ${required} must be answered` : count;
	}

	function questionTypes(template: ChecklistTemplate) {
		const seen = new Set(template.items.map((item) => CHECKLIST_ITEM_TYPE_LABELS[item.item_type]));
		return [...seen].join(', ');
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Checklist' },
		{ key: 'questions', label: 'Questions' },
		{ key: 'types', label: 'Answer types' },
		{ key: 'status', label: 'Status' }
	];
</script>

<svelte:head><title>Checklists · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Checklists' }]}
	/>

	<PageHeader
		eyebrow="Work"
		title="Checklists"
		description="Build a checklist once, attach it to a job, and every visit on that job gets its own copy to fill in."
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Checklists could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const data = query.data}

		<SectionBlock title="Your checklists" level={2}>
			{#snippet actions()}
				{#if data.can_manage}
					<Button size="small" onclick={() => (dialog = { template: null })}>New checklist</Button>
				{/if}
			{/snippet}

			{#if data.templates.length === 0}
				<EmptyState
					icon={checklistIcon}
					title="No checklists yet"
					description="A checklist is the list of things the crew confirms on site — gate locked, photos taken, height chosen. Build one and attach it to a job."
				>
					{#snippet action()}
						{#if data.can_manage}
							<Button variant="secondary" onclick={() => (dialog = { template: null })}>
								Build a checklist
							</Button>
						{/if}
					{/snippet}
				</EmptyState>
			{:else}
				<DataTable
					{columns}
					items={data.templates}
					rowId={(template) => template.id}
					caption="Reusable checklists"
				>
					{#snippet row(template: ChecklistTemplate)}
						<th scope="row">{template.name}</th>
						<td>{summary(template)}</td>
						<td class="checklists-page__types">{questionTypes(template)}</td>
						<td>
							<StatusBadge status={template.archived ? 'inactive' : 'success'}>
								{template.archived ? 'Archived' : 'In use'}
							</StatusBadge>
						</td>
					{/snippet}
					{#snippet rowActions(template: ChecklistTemplate)}
						{#if data.can_manage}
							<DropdownMenu
								triggerLabel={`Actions for ${template.name}`}
								disabled={archiving === template.id}
								items={menuItems(template)}
							/>
						{/if}
					{/snippet}
				</DataTable>
			{/if}
		</SectionBlock>
	{/if}
</PageContainer>

<ChecklistTemplateDialog
	open={dialog !== null}
	template={dialog?.template ?? null}
	onSaved={saved}
	onClose={() => (dialog = null)}
/>

<style lang="scss">
	.checklists-page__types {
		color: var(--color-text--secondary);
	}
</style>
