<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ProtectedDocumentHistory from '$lib/components/setup/ProtectedDocumentHistory.svelte';
	import { formatFileSize } from '$lib/files/api';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import {
		organizationProtectedDocumentsQuery,
		protectedDocumentUrl,
		type ProtectedDocumentListing
	} from '$lib/jafar/organization-setup-queries';
	import {
		jafarOrganizationKey,
		jafarOrganizationProtectedDocumentsKey
	} from '$lib/jafar/query-keys';
	import { formatCalendarDate, formatDateTime } from './format';

	// Client onboarding B9b (plan §8 "protected provider-document status"): the papers a client uploaded for a
	// provider step — a phone bill to move their number, a tax letter for texting registration. Jafar opens one
	// when he submits the step, marks the step finished so it is deleted 90 days later, or deletes it now
	// (Jafar's decisions 1, 4 and 5, 2026-10-04). Every opening and deletion is recorded in its history, which
	// the client's owner sees too. Stage C adds the client's setup answers to this tab.
	let {
		organizationId,
		preview
	}: {
		organizationId: string | undefined;
		preview: OrganizationDetailPreview | null;
	} = $props();

	const queryClient = useQueryClient();
	const documentsQuery = createQuery(() => ({
		...organizationProtectedDocumentsQuery(organizationId ?? ''),
		enabled: !preview && Boolean(organizationId)
	}));

	type Pending = { kind: 'finish' | 'delete'; document: ProtectedDocumentListing };
	let pending = $state<Pending | null>(null);
	let actionError = $state('');

	const action = createMutation(() => ({
		mutationFn: async ({ kind, document }: Pending) => {
			const response = await fetch(protectedDocumentUrl(organizationId ?? '', document.id), {
				method: kind === 'delete' ? 'DELETE' : 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: kind === 'delete' ? undefined : JSON.stringify({ provider_step_finished: true })
			});
			if (!response.ok) {
				const result = (await response.json().catch(() => ({}))) as { error?: string };
				throw new Error(result.error ?? 'That could not be saved. Try again.');
			}
		},
		onSuccess: () => {
			pending = null;
		},
		onError: (error) => {
			actionError = error.message;
		},
		onSettled: (_data, _error, { document }) => {
			void queryClient.invalidateQueries({
				queryKey: jafarOrganizationProtectedDocumentsKey(organizationId)
			});
			void queryClient.invalidateQueries({ queryKey: historyKey(document.id) });
		}
	}));

	const historyKey = (documentId: string) => [
		...jafarOrganizationKey(organizationId),
		'protected-document-history',
		documentId
	];

	function ask(kind: Pending['kind'], document: ProtectedDocumentListing) {
		actionError = '';
		pending = { kind, document };
	}

	const columns: DataTableColumn[] = [
		{ key: 'document', label: 'Document' },
		{ key: 'status', label: 'Status' },
		{ key: 'uploaded', label: 'Uploaded' },
		{ key: 'deletion', label: 'Deletion' }
	];

	function status(document: ProtectedDocumentListing): {
		label: string;
		tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
	} {
		switch (document.state) {
			case 'uploading':
				return { label: 'Upload not finished', tone: 'inactive' };
			case 'checking':
				return { label: 'Checking for viruses', tone: 'informative' };
			case 'refused':
				return { label: 'Refused', tone: 'critical' };
			case 'deleted':
				return { label: 'Deleted', tone: 'inactive' };
			default:
				return document.in_answer
					? { label: 'Ready', tone: 'success' }
					: { label: 'Not in an answer', tone: 'warning' };
		}
	}

	function deletion(document: ProtectedDocumentListing) {
		if (document.deleted_at) return `Deleted ${formatDateTime(document.deleted_at)}`;
		if (document.delete_after)
			return `Deletes on ${formatCalendarDate(document.delete_after.slice(0, 10))}`;
		return 'Kept until the provider step is finished';
	}

	function menu(document: ProtectedDocumentListing) {
		const live = document.state !== 'deleted' && document.state !== 'refused';
		return [
			...(live && !document.delete_after
				? [
						{
							label: 'Provider step finished',
							icon: checkIcon,
							onSelect: () => ask('finish', document)
						}
					]
				: []),
			...(live
				? [
						{
							label: 'Delete now',
							icon: trashIcon,
							destructive: true,
							onSelect: () => ask('delete', document)
						}
					]
				: [])
		];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="setup">
	<SectionBlock
		title="Protected documents"
		icon={shieldLockIcon}
		hint="Papers the client uploaded for a provider step. Only the business owner and you can open them, and every opening is recorded."
	>
		{#if preview}
			<EmptyState
				title="No protected documents"
				description="Sample organizations have no setup uploads."
			/>
		{:else if documentsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading protected documents" />
		{:else if documentsQuery.isError}
			<ErrorState
				description={documentsQuery.error.message}
				retry={() => documentsQuery.refetch()}
			/>
		{:else if documentsQuery.data.length === 0}
			<EmptyState
				title="No protected documents"
				description="When the client uploads a phone bill or tax letter in setup, it appears here."
				icon={shieldLockIcon}
			/>
		{:else}
			<DataTable
				caption="Protected documents"
				{columns}
				items={documentsQuery.data}
				rowId={(document) => document.id}
			>
				{#snippet row(document)}
					{@const shown = status(document)}
					<td>
						<span class="setup-workspace__name">{document.name}</span>
						<span class="setup-workspace__secondary">
							{document.question}{document.size_bytes
								? ` · ${formatFileSize(document.size_bytes)}`
								: ''}
						</span>
					</td>
					<td>
						<Badge status={shown.tone} size="small">{shown.label}</Badge>
						{#if document.problem}
							<span class="setup-workspace__secondary">{document.problem}</span>
						{/if}
					</td>
					<td>{document.uploaded_at ? formatDateTime(document.uploaded_at) : '—'}</td>
					<td>{deletion(document)}</td>
				{/snippet}
				{#snippet rowActions(document)}
					{@const items = menu(document)}
					<div class="setup-workspace__row-actions">
						{#if document.state === 'ready'}
							<!-- A click, never a link: hovering must not fetch it, as every opening is recorded. -->
							<Button
								size="small"
								variant="secondary"
								onclick={() =>
									window.location.assign(protectedDocumentUrl(organizationId ?? '', document.id))}
								>Open</Button
							>
						{/if}
						<ProtectedDocumentHistory
							url={`${protectedDocumentUrl(organizationId ?? '', document.id)}/history`}
							queryKey={historyKey(document.id)}
							name={document.name}
						/>
						{#if items.length}
							<DropdownMenu triggerLabel={`More actions for ${document.name}`} {items} />
						{/if}
					</div>
				{/snippet}
			</DataTable>
		{/if}
	</SectionBlock>
</TabPanel>

{#if pending}
	<ConfirmDialog
		open
		title={pending.kind === 'delete'
			? `Delete ${pending.document.name} now?`
			: 'Mark the provider step finished?'}
		icon={pending.kind === 'delete' ? trashIcon : checkIcon}
		tone={pending.kind === 'delete' ? 'critical' : 'default'}
		destructive={pending.kind === 'delete'}
		confirmLabel={pending.kind === 'delete' ? 'Delete now' : 'Mark finished'}
		loading={action.isPending}
		onConfirm={() => pending && action.mutate(pending)}
		onClose={() => {
			if (!action.isPending) pending = null;
		}}
	>
		<p>
			{pending.kind === 'delete'
				? 'The file is removed from storage for good, and nobody can open it again. Its history stays, and the client sees that Uplift deleted it.'
				: `${pending.document.name} will be deleted automatically 90 days from today. Until then the business owner and you can still open it. This can't be undone.`}
		</p>
		{#if actionError}
			<p class="setup-workspace__error" role="alert">{actionError}</p>
		{/if}
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-workspace {
		&__name {
			display: block;
			color: var(--color-heading);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__secondary {
			display: block;
			margin-top: 2px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__row-actions {
			display: flex;
			align-items: center;
			justify-content: flex-end;
			gap: var(--space-smaller);
		}

		&__error {
			margin: var(--space-small) 0 0;
			color: var(--color-critical--onSurface);
		}
	}
</style>
