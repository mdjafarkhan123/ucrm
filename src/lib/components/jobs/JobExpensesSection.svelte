<script lang="ts">
	import { page } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import JobExpenseDialog from '$lib/components/jobs/JobExpenseDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		addJobExpense,
		deleteJobExpense,
		fetchJobExpenses,
		jobExpensesKey,
		updateJobExpense,
		type JobExpense,
		type JobExpenseInput,
		type JobWriteError
	} from '$lib/jobs/api';
	import { attachmentsKey, deleteAttachment, fetchAttachments } from '$lib/collaboration/api';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// The expenses run up on this job, the way Jobber's Expenses block reads: what it was, when, who to pay
	// back, and what it cost us. The section owns its own query rather than riding on the job payload, because
	// who may see these rows — and whether the money is on them at all — is a different question from who may
	// open the job. Money here is never assembled in the browser: `job_expenses_list` leaves the total off a
	// row entirely for a reader without jobs.view_cost, so there is nothing to accidentally render.
	let {
		jobId,
		locale = 'en-US',
		currencyCode = 'USD',
		onChange
	}: {
		jobId: string;
		locale?: string;
		currencyCode?: string;
		/** Called after an expense is recorded, corrected or removed, so the page can refresh the costing card. */
		onChange?: () => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();
	const currentUserId = $derived((page.data.user?.id as string | undefined) ?? '');

	const expensesQuery = createQuery(() => ({
		queryKey: jobExpensesKey(jobId),
		queryFn: () => fetchJobExpenses(jobId),
		enabled: Boolean(jobId),
		staleTime: 15_000
	}));
	const data = $derived(expensesQuery.data);
	const expenses = $derived<JobExpense[]>(data?.expenses ?? []);

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);

	function reimburseLabel(expense: JobExpense) {
		if (!expense.reimburse_to_user_id) return null;
		return `Reimburse ${expense.reimburse_to_name ?? 'a team member'}`;
	}

	// --- Recording and correcting ------------------------------------------------------------------------
	let dialogOpen = $state(false);
	let editing = $state<JobExpense | null>(null);

	function openAdd() {
		editing = null;
		dialogOpen = true;
	}

	function openEdit(expense: JobExpense) {
		editing = expense;
		dialogOpen = true;
	}

	// The dialog writes the expense and hands the id straight to its receipt card, so the write returns the
	// id rather than swallowing it. It throws on failure, which the dialog turns into its own error line.
	async function writeExpense(input: JobExpenseInput): Promise<string> {
		if (editing) {
			const result = await updateJobExpense(jobId, editing.id, input);
			return result.id;
		}
		const result = await addJobExpense(jobId, input);
		return result.id;
	}

	async function onSaved(message: string) {
		dialogOpen = false;
		editing = null;
		await expensesQuery.refetch();
		onChange?.();
		toast.success(message);
	}

	function menuItems(expense: JobExpense) {
		return [
			{ label: 'Edit expense', icon: pencilIcon, onSelect: () => openEdit(expense) },
			{
				label: 'Remove expense',
				icon: trashIcon,
				onSelect: () => (confirmRemove = expense),
				destructive: true
			}
		];
	}

	// --- Removing --------------------------------------------------------------------------------------
	let confirmRemove = $state<JobExpense | null>(null);
	let busyId = $state('');

	async function reallyRemove() {
		const expense = confirmRemove;
		if (!expense || busyId) return;
		busyId = expense.id;
		try {
			// R2 is reachable only from the attachment route, so a receipt's file has to be removed there
			// before the expense row goes — otherwise it sits in the bucket forever with nothing pointing at
			// it. Best-effort per file: the expense is still removed even if a receipt refuses to.
			if (expense.receipt_count > 0) {
				const files = await fetchAttachments('job_expense', expense.id);
				for (const file of files) {
					try {
						await deleteAttachment(file.id);
					} catch (fileError) {
						console.error('Could not delete a receipt before removing an expense.', fileError);
					}
				}
				void queryClient.invalidateQueries({
					queryKey: attachmentsKey('job_expense', expense.id)
				});
			}

			await deleteJobExpense(jobId, expense.id);
			confirmRemove = null;
			await expensesQuery.refetch();
			onChange?.();
			toast.success('Expense removed');
		} catch (cause) {
			toast.error((cause as JobWriteError).message ?? 'That expense could not be removed.');
		} finally {
			busyId = '';
		}
	}
</script>

<SectionBlock title="Expenses" icon={receiptIcon} level={2}>
	{#snippet actions()}
		{#if data?.can_add}
			<Button variant="tertiary" size="small" onclick={openAdd}>Add expense</Button>
		{/if}
	{/snippet}

	{#if expensesQuery.isPending}
		<LoadingSkeleton variant="text" label="Loading expenses" rows={3} />
	{:else if expensesQuery.isError}
		<p class="job-expenses__note">The expenses on this job could not be loaded.</p>
	{:else if expenses.length === 0}
		<EmptyState
			icon={receiptIcon}
			title="No expenses recorded"
			description={data?.can_manage_team
				? 'Materials, dump fees and subcontractors show up here, with what they cost.'
				: 'Expenses you record on this job show up here.'}
		/>
	{:else}
		<ul class="job-expenses">
			{#each expenses as expense (expense.id)}
				<li class="job-expenses__item" class:job-expenses__item--busy={busyId === expense.id}>
					<div class="job-expenses__body">
						<p class="job-expenses__name">
							{expense.name}
							{#if expense.receipt_count > 0}
								<span
									class="job-expenses__receipt"
									title={`${expense.receipt_count} receipt${expense.receipt_count === 1 ? '' : 's'}`}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html paperclipIcon}{expense.receipt_count}
								</span>
							{/if}
						</p>
						<p class="job-expenses__meta">
							{dateFormat.format(new Date(`${expense.expense_date}T12:00:00`))}
							{#if expense.accounting_code}· {expense.accounting_code}{/if}
							{#if reimburseLabel(expense)}· {reimburseLabel(expense)}{/if}
						</p>
						{#if expense.description}<p class="job-expenses__desc">{expense.description}</p>{/if}
					</div>

					<div class="job-expenses__side">
						{#if data?.can_see_cost}
							<span class="job-expenses__cost"
								>{money.format((expense.total_minor ?? 0) / 100)}</span
							>
						{/if}
						{#if expense.can_edit}
							<DropdownMenu
								items={menuItems(expense)}
								triggerLabel="Expense actions"
								disabled={busyId === expense.id}
							/>
						{/if}
					</div>
				</li>
			{/each}
		</ul>

		<div class="job-expenses__totals">
			<p class="job-expenses__total">
				<span>{data?.can_manage_team ? 'Expenses' : 'Your expenses'}</span>
				<strong>{data?.totals.expense_count ?? 0}</strong>
			</p>
			{#if data?.can_see_cost}
				<p class="job-expenses__total">
					<span>Expense cost</span>
					<strong>{money.format((data.totals.total_minor ?? 0) / 100)}</strong>
				</p>
			{/if}
		</div>

		{#if data?.has_more}
			<p class="job-expenses__note">
				Showing the 200 most recent expenses. The total above counts every one.
			</p>
		{/if}
	{/if}
</SectionBlock>

<JobExpenseDialog
	open={dialogOpen}
	expense={editing}
	{locale}
	{currencyCode}
	canManageTeam={Boolean(data?.can_manage_team)}
	{currentUserId}
	{writeExpense}
	{onSaved}
	onClose={() => {
		dialogOpen = false;
		editing = null;
	}}
/>

<ConfirmDialog
	open={confirmRemove !== null}
	title="Remove this expense?"
	confirmLabel="Remove expense"
	destructive
	loading={busyId !== '' && busyId === confirmRemove?.id}
	onConfirm={() => void reallyRemove()}
	onClose={() => {
		if (!busyId) confirmRemove = null;
	}}
>
	This takes the expense off the job and its cost, along with any receipts. A record of the removal
	is kept in the job's costing history.
</ConfirmDialog>

<style lang="scss">
	.job-expenses {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		&__item {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
				padding-top: var(--space-base);
			}

			&--busy {
				opacity: 0.5;
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__name {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__receipt {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__meta,
		&__desc {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__desc {
			color: var(--color-text);
		}

		&__side {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			flex-shrink: 0;
		}

		&__cost {
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}

		&__totals {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			padding-top: var(--space-base);
		}

		&__total {
			display: flex;
			align-items: baseline;
			gap: var(--space-small);
			margin: 0;

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			strong {
				color: var(--color-heading);
				font-variant-numeric: tabular-nums;
			}
		}
	}

	.job-expenses__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
