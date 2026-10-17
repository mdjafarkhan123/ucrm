<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
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
	import { FORM_OUTCOME_LABELS } from '$lib/forms/labels';
	import type { FormListItem, FormOutcome } from '$lib/forms/types';
	import fileFormIcon from '@tabler/icons/outline/forms.svg?raw';
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';
	import calendarSearchIcon from '@tabler/icons/outline/calendar-search.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import clipboardTextIcon from '@tabler/icons/outline/clipboard-text.svg?raw';
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
				`“${form.name}” is now the default ${FORM_OUTCOME_LABELS[form.outcome].toLowerCase()}.`
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

	// Each kind of form wears the colour of what it leads to: a request is orange, an assessment visit
	// yellow, a booked job green.
	const outcomeIcons: Record<FormOutcome, string> = {
		request: clipboardTextIcon,
		assessment: calendarSearchIcon,
		job: calendarCheckIcon
	};

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Form' },
		{ key: 'type', label: 'Type', width: '260px' },
		{ key: 'status', label: 'Status', width: '260px' }
	];
</script>

<svelte:head><title>Request Forms · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<SettingsPageHeader
		title="Request Forms"
		description="Build the forms customers fill in to reach you online. Publish one to make it live, and mark one as your default."
		icon={clipboardTextIcon}
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if query.isError}
		<ErrorState description="Your forms could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const forms = query.data}

		<RecordListCard title="Your forms" padBody={forms.length === 0}>
			{#snippet toolbar()}
				<Button size="small" onclick={() => (creating = true)}>New form</Button>
			{/snippet}

			{#if forms.length === 0}
				<EmptyState
					icon={fileFormIcon}
					title="No forms yet"
					description="A form is the page customers use to reach you online — to ask for work, book an assessment, or book a job straight onto your calendar. Build one, add your questions, and publish it to share."
				>
					{#snippet action()}
						<Button variant="secondary" onclick={() => (creating = true)}>Build a form</Button>
					{/snippet}
				</EmptyState>
			{:else}
				<DataTable
					variant="card"
					{columns}
					items={forms}
					rowId={(form) => form.id}
					caption="Request and booking forms"
				>
					{#snippet row(form: FormListItem)}
						{@const badge = statusOf(form)}
						<th scope="row">
							<span class="forms-page__form">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								<span class={`forms-page__icon forms-page__icon--${form.outcome}`} aria-hidden="true"
									>{@html outcomeIcons[form.outcome]}</span
								>
								<a class="forms-page__name" href={builderHref(form.id)}>{form.name}</a>
								{#if form.is_default}
									<span class="forms-page__default">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										<span aria-hidden="true">{@html starIcon}</span>Default
									</span>
								{/if}
							</span>
						</th>
						<td class="forms-page__muted">{FORM_OUTCOME_LABELS[form.outcome]}</td>
						<td><StatusBadge status={badge.status} size="compact">{badge.label}</StatusBadge></td>
					{/snippet}
					{#snippet rowActions(form: FormListItem)}
						<DropdownMenu
							triggerLabel={`Actions for ${form.name}`}
							triggerIcon={dotsIcon}
							disabled={busy === form.id}
							items={menuItems(form)}
						/>
					{/snippet}
				</DataTable>
			{/if}
		</RecordListCard>
	{/if}
</PageContainer>

<FormCreateDialog open={creating} {onCreated} onClose={() => (creating = false)} />

<style lang="scss">
	.forms-page {
		&__form {
			display: flex;
			align-items: center;
			gap: 12px;
		}

		&__icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 36px;
			height: 36px;
			border-radius: 10px;

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&--request {
				background: var(--color-request--surface);
				color: var(--color-request);
			}
			&--assessment {
				background: var(--color-warning--surface);
				color: var(--color-warning--onSurface);
			}
			&--job {
				background: var(--color-job--surface);
				color: var(--color-job);
			}
		}

		&__name {
			color: var(--color-heading);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				color: var(--color-interactive);
				text-decoration: underline;
			}
			&:focus-visible {
				outline: 2px solid var(--color-interactive);
				outline-offset: 2px;
				border-radius: var(--radius-small);
			}
		}

		&__default {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 3px 8px 3px 6px;
			border-radius: var(--radius-large);
			background: var(--color-surface--reverse);
			color: var(--color-text--reverse);
			font-size: 11px;
			font-weight: 700;

			:global(svg) {
				width: 11px;
				height: 11px;
			}
		}

		&__muted {
			color: var(--color-text--secondary);
		}
	}
</style>
