<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
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
	import FormCreateDialog from '$lib/components/settings/forms/FormCreateDialog.svelte';
	import {
		fetchForms,
		formsKey,
		setFormArchived,
		setFormDefault,
		type FormApiError,
		type FormCreateResult
	} from '$lib/forms/api';
	import type { FormListItem, FormOutcome } from '$lib/forms/types';
	import fileFormIcon from '@tabler/icons/outline/forms.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import archiveOffIcon from '@tabler/icons/outline/archive-off.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Archived forms stay in the list behind a badge, same as checklists — a published link that used one
	// still points at it, so removal is reversible rather than a hard delete.
	const query = createQuery(() => ({
		queryKey: formsKey(true),
		queryFn: () => fetchForms(true)
	}));

	let creating = $state(false);
	let busy = $state<string | null>(null);

	const OUTCOME_LABELS: Record<FormOutcome, string> = {
		request: 'Request form',
		assessment: 'Assessment booking',
		job: 'Job booking'
	};

	function builderHref(id: string) {
		return resolve('/(app)/settings/forms/[id]', { id });
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: ['settings', 'forms'] });
	}

	function onCreated(result: FormCreateResult) {
		creating = false;
		void invalidate();
		void goto(builderHref(result.form_id));
	}

	async function makeDefault(form: FormListItem) {
		busy = form.id;
		try {
			await setFormDefault(form.id, form.revision);
			await invalidate();
			toast.success(
				`“${form.name}” is now the default ${OUTCOME_LABELS[form.outcome].toLowerCase()}.`
			);
		} catch (cause) {
			toast.error(errorText(cause));
		} finally {
			busy = null;
		}
	}

	async function toggleArchived(form: FormListItem) {
		busy = form.id;
		const archiving = form.archived_at === null;
		try {
			await setFormArchived(form.id, archiving, form.revision);
			await invalidate();
			toast.success(archiving ? 'Form archived.' : 'Form restored.');
		} catch (cause) {
			toast.error(errorText(cause));
		} finally {
			busy = null;
		}
	}

	function errorText(cause: unknown): string {
		const err = cause as FormApiError;
		if (err?.reason === 'stale_revision')
			return 'Someone else changed this form. Refreshing the list.';
		return err instanceof Error ? err.message : 'That could not be done.';
	}

	function menuItems(form: FormListItem) {
		const items = [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => void goto(builderHref(form.id)) }
		];
		if (form.archived_at === null && !form.is_default && form.published_version_number !== null) {
			items.push({
				label: 'Set as default',
				icon: starIcon,
				onSelect: () => void makeDefault(form)
			});
		}
		items.push(
			form.archived_at !== null
				? { label: 'Restore', icon: archiveOffIcon, onSelect: () => void toggleArchived(form) }
				: { label: 'Archive', icon: archiveIcon, onSelect: () => void toggleArchived(form) }
		);
		return items;
	}

	function statusOf(form: FormListItem): {
		status: 'success' | 'warning' | 'informative' | 'inactive';
		label: string;
	} {
		if (form.archived_at !== null) return { status: 'inactive', label: 'Archived' };
		if (form.published_version_number !== null && form.has_draft)
			return { status: 'informative', label: 'Published · edits not live' };
		if (form.published_version_number !== null) return { status: 'success', label: 'Published' };
		return { status: 'warning', label: 'Draft' };
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Form' },
		{ key: 'type', label: 'Type' },
		{ key: 'status', label: 'Status' }
	];
</script>

<svelte:head><title>Request Forms · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Request Forms' }]}
	/>

	<PageHeader
		eyebrow="Business"
		title="Request Forms"
		description="Build the forms customers fill in to reach you online. Publish one to make it live, and mark one as your default."
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Your forms could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const forms = query.data}

		<SectionBlock title="Your forms" level={2}>
			{#snippet actions()}
				<Button size="small" onclick={() => (creating = true)}>New request form</Button>
			{/snippet}

			{#if forms.length === 0}
				<EmptyState
					icon={fileFormIcon}
					title="No forms yet"
					description="A request form is the page customers use to ask you for work. Build one, add your questions, and publish it to share."
				>
					{#snippet action()}
						<Button variant="secondary" onclick={() => (creating = true)}
							>Build a request form</Button
						>
					{/snippet}
				</EmptyState>
			{:else}
				<DataTable
					{columns}
					items={forms}
					rowId={(form) => form.id}
					caption="Request and booking forms"
				>
					{#snippet row(form: FormListItem)}
						{@const badge = statusOf(form)}
						<th scope="row">
							<a class="forms-page__name" href={builderHref(form.id)}>{form.name}</a>
							{#if form.is_default}
								<span class="forms-page__default">Default</span>
							{/if}
						</th>
						<td class="forms-page__muted">{OUTCOME_LABELS[form.outcome]}</td>
						<td><StatusBadge status={badge.status}>{badge.label}</StatusBadge></td>
					{/snippet}
					{#snippet rowActions(form: FormListItem)}
						<DropdownMenu
							triggerLabel={`Actions for ${form.name}`}
							disabled={busy === form.id}
							items={menuItems(form)}
						/>
					{/snippet}
				</DataTable>
			{/if}
		</SectionBlock>
	{/if}
</PageContainer>

<FormCreateDialog open={creating} {onCreated} onClose={() => (creating = false)} />

<style lang="scss">
	.forms-page {
		&__name {
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}

		&__default {
			display: inline-block;
			margin-left: var(--space-small);
			padding: 2px 8px;
			border-radius: var(--radius-large);
			background: var(--color-interactive--background);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			vertical-align: middle;
		}

		&__muted {
			color: var(--color-text--secondary);
		}
	}
</style>
