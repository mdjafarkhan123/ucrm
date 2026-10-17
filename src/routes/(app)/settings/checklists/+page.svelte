<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
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
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';
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

	function requiredCount(template: ChecklistTemplate) {
		return template.items.filter((item) => item.required).length;
	}

	/** The answer types a checklist asks for, each named once, in the order its questions use them. */
	function questionTypes(template: ChecklistTemplate) {
		return [...new Set(template.items.map((item) => CHECKLIST_ITEM_TYPE_LABELS[item.item_type]))];
	}

	function requiredShare(template: ChecklistTemplate) {
		return template.items.length === 0 ? 0 : (requiredCount(template) / template.items.length) * 100;
	}
</script>

<svelte:head><title>Checklists · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<SettingsPageHeader
		title="Checklists"
		description="Build a checklist once, attach it to a job, and every visit on that job gets its own copy to fill in."
		icon={checklistIcon}
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Checklists could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const data = query.data}

		<div class="checklists-page__bar">
			<h2 class="checklists-page__heading">
				Your checklists
				<span class="checklists-page__count">{data.templates.length}</span>
			</h2>
			{#if data.can_manage}
				<Button size="small" onclick={() => (dialog = { template: null })}>New checklist</Button>
			{/if}
		</div>

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
			<ul class="checklists-page__grid" aria-label="Reusable checklists">
				{#each data.templates as template (template.id)}
					{@const required = requiredCount(template)}
					<li class="checklists-card" class:checklists-card--archived={template.archived}>
						<div class="checklists-card__top">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span class="checklists-card__icon" aria-hidden="true">{@html checklistIcon}</span>
							<StatusBadge status={template.archived ? 'inactive' : 'success'} size="compact">
								{template.archived ? 'Archived' : 'In use'}
							</StatusBadge>
							{#if data.can_manage}
								<DropdownMenu
									triggerLabel={`Actions for ${template.name}`}
									triggerIcon={dotsIcon}
									disabled={archiving === template.id}
									items={menuItems(template)}
								/>
							{/if}
						</div>
						<h3 class="checklists-card__name">{template.name}</h3>
						<div class="checklists-card__count">
							<p>
								<strong>{template.items.length}</strong>
								{template.items.length === 1 ? 'question' : 'questions'}
							</p>
							<span class="checklists-card__required">
								{required > 0 ? `${required} must be answered` : 'None required'}
							</span>
						</div>
						<div class="checklists-card__bar" aria-hidden="true">
							<span style:width={`${requiredShare(template)}%`}></span>
						</div>
						<ul class="checklists-card__types" aria-label="Answer types">
							{#each questionTypes(template) as type (type)}
								<li>{type}</li>
							{/each}
						</ul>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</PageContainer>

<ChecklistTemplateDialog
	open={dialog !== null}
	template={dialog?.template ?? null}
	onSaved={saved}
	onClose={() => (dialog = null)}
/>

<style lang="scss">
	.checklists-page {
		&__bar {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin-bottom: var(--space-base);
		}
		&__heading {
			display: flex;
			align-items: center;
			gap: 10px;
			color: var(--color-heading);
			font-size: 20px;
			font-weight: 800;
		}
		&__count {
			padding: 2px 9px;
			border: 1px solid var(--color-border);
			border-radius: 12px;
			background: var(--color-surface);
			color: var(--color-text);
			font-size: 12px;
			font-weight: 700;
		}
		&__grid {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}
	}

	.checklists-card {
		display: grid;
		align-content: start;
		gap: 14px;
		padding: 18px 20px 20px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&__top {
			display: flex;
			align-items: center;
			gap: 6px;

			:global(.status-badge) {
				margin-left: auto;
			}
		}
		&__icon {
			display: grid;
			place-items: center;
			width: 40px;
			height: 40px;
			border-radius: 12px;
			background: var(--color-job--surface);
			color: var(--color-job);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
		&__name {
			overflow-wrap: anywhere;
			color: var(--color-heading);
			font-size: 17px;
			font-weight: 800;
			line-height: 1.25;
		}
		&__count {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: 8px;
			color: var(--color-text--secondary);
			font-size: 14px;

			strong {
				color: var(--color-heading);
				font-size: 26px;
				font-weight: 800;
				letter-spacing: -0.5px;
			}
		}
		&__required {
			color: var(--color-interactive);
			font-size: 12px;
			font-weight: 700;
		}
		&__bar {
			height: 6px;
			overflow: hidden;
			border-radius: 3px;
			background: var(--color-surface--background);

			span {
				display: block;
				height: 100%;
				border-radius: 3px;
				background: var(--color-interactive);
			}
		}
		&__types {
			display: flex;
			flex-wrap: wrap;
			gap: 6px;
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				padding: 4px 9px;
				border: 1px solid var(--color-border);
				border-radius: 6px;
				background: var(--color-surface--background--subtle);
				color: var(--color-text--secondary);
				font-size: 12px;
				font-weight: 500;
			}
		}
		&--archived {
			.checklists-card__name,
			.checklists-card__count strong {
				color: var(--color-text--secondary);
			}
			.checklists-card__icon {
				background: var(--color-surface--background);
				color: var(--color-text--secondary);
			}
			.checklists-card__required {
				color: var(--color-text--secondary);
			}
			.checklists-card__bar span {
				background: var(--color-text--secondary);
			}
		}
	}

	@media (max-width: 1079px) {
		.checklists-page__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 639px) {
		.checklists-page__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
