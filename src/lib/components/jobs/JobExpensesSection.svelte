<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
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
	import { detachFileFromRecord, fetchFiles } from '$lib/files/api';
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
			// A receipt is a File like any other: removing the expense takes it off this record, the same
			// "Remove from this record" every other file card does. The File itself, its stored object, and
			// any other use it has stay untouched — it never belonged only to this expense.
			if (expense.receipt_count > 0) {
				const { files } = await fetchFiles({
					view: 'on_record',
					folderId: '',
					search: '',
					entityType: 'job_expense',
					entityId: expense.id
				});
				for (const file of files) {
					try {
						await detachFileFromRecord(file.id, 'job_expense', expense.id);
					} catch (fileError) {
						console.error('Could not take a receipt off an expense before removing it.', fileError);
					}
				}
				void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
				void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
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

<SectionBlock
	title="Expenses"
	icon={receiptIcon}
	tone="invoice"
	subtitle="Materials and costs paid for this job"
	level={2}
	class="section-block--flush"
>
	{#snippet actions()}
		{#if data?.can_add}
			<Button variant="tertiary" size="small" onclick={openAdd}>
				{@html plusIcon}Add expense
			</Button>
		{/if}
	{/snippet}

	{#if expensesQuery.isPending}
		<div class="job-expenses__pad">
			<LoadingSkeleton variant="text" label="Loading expenses" rows={3} />
		</div>
	{:else if expensesQuery.isError}
		<p class="job-expenses__note job-expenses__pad">
			The expenses on this job could not be loaded.
		</p>
	{:else if expenses.length === 0}
		<div class="job-expenses__pad">
			<EmptyState
				icon={receiptIcon}
				title="No expenses recorded"
				description={data?.can_manage_team
					? 'Materials, dump fees and subcontractors show up here, with what they cost.'
					: 'Expenses you record on this job show up here.'}
			/>
		</div>
	{:else}
		<ul class="job-expenses">
			{#each expenses as expense (expense.id)}
				<li class="job-expenses__item" class:job-expenses__item--busy={busyId === expense.id}>
					<IconTile icon={receiptIcon} tone="invoice" />
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
							{#if reimburseLabel(expense)}· {reimburseLabel(expense)}{/if}
						</p>
						{#if expense.description}<p class="job-expenses__desc">{expense.description}</p>{/if}
					</div>

					<span class="job-expenses__code">{expense.accounting_code ?? ''}</span>
					{#if data?.can_see_cost}
						<span class="job-expenses__cost">{money.format((expense.total_minor ?? 0) / 100)}</span>
					{/if}
					<span class="job-expenses__menu">
						{#if expense.can_edit}
							<DropdownMenu
								items={menuItems(expense)}
								triggerLabel="Expense actions"
								disabled={busyId === expense.id}
							/>
						{/if}
					</span>
				</li>
			{/each}
		</ul>

		<div class="job-expenses__totals">
			<p class="job-expenses__total">
				<span
					>{data?.can_see_cost ? 'Expense cost · ' : ''}{data?.totals.expense_count ?? 0}
					{(data?.totals.expense_count ?? 0) === 1 ? 'expense' : 'expenses'}</span
				>
				{#if data?.can_see_cost}
					<strong>{money.format((data.totals.total_minor ?? 0) / 100)}</strong>
				{/if}
			</p>
			{#if data?.has_more}
				<p class="job-expenses__note">
					Showing the 200 most recent expenses. The total above counts every one.
				</p>
			{/if}
		</div>
	{/if}
</SectionBlock>

<JobExpenseDialog
	open={dialogOpen}
	expense={editing}
	{locale}
	{currencyCode}
	canManageTeam={Boolean(data?.can_manage_team)}
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
	// Concept look (Job details `tNdkX`): a receipt tile, the expense, its accounting code and cost in
	// right-hand columns, and the total in a tinted strip along the card's foot.
	.job-expenses {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: var(--space-smaller) var(--space-medium);
		list-style: none;

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			&--busy {
				opacity: 0.5;
			}
		}

		&__body {
			display: flex;
			flex: 1 1 auto;
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
			font-size: var(--typography--fontSize-base);
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

		&__code {
			flex: 0 0 90px;
			overflow: hidden;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			text-align: right;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__cost {
			flex: 0 0 90px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-align: right;
			font-variant-numeric: tabular-nums;
		}

		&__menu {
			display: inline-flex;
			flex: 0 0 32px;
			justify-content: flex-end;
		}

		&__totals {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		&__total {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin: 0;

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
				font-variant-numeric: tabular-nums;
			}
		}

		&__pad {
			padding: var(--space-medium);
		}
	}

	.job-expenses__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
