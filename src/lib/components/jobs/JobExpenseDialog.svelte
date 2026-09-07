<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import type { CalendarDate } from '@internationalized/date';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { JobExpense, JobExpenseInput, JobWriteError } from '$lib/jobs/api';

	// One expense, recorded or corrected — the twin of the time-entry dialog. Jobber's form is matched field
	// for field: item name, accounting code, description, date, total, who to pay back, and a receipt. The
	// total is money, so it lives behind jobs.view_price on the reader; the person recording it typed it, so
	// it is here. The receipt is a real attachment: the AttachmentsCard stages the picked files and this
	// dialog's Save is the button that writes them, right after the expense itself is written and its id is
	// known — the same "no write without a save button" rule the card follows on a page.
	let {
		open,
		expense = null,
		locale = 'en-US',
		currencyCode = 'USD',
		canManageTeam = false,
		currentUserId = '',
		writeExpense,
		onSaved,
		onClose
	}: {
		open: boolean;
		/** The expense being corrected, or null when recording a new one. */
		expense?: JobExpense | null;
		locale?: string;
		currencyCode?: string;
		/** Whether this person may pick anyone to reimburse. Without it the list is still shown for context. */
		canManageTeam?: boolean;
		currentUserId?: string;
		/** Writes the expense and resolves with its id, or throws a JobWriteError. */
		writeExpense: (input: JobExpenseInput) => Promise<string>;
		/** Called after the expense and its receipts are saved. */
		onSaved: (message: string) => void;
		onClose: () => void;
	} = $props();

	let name = $state('');
	let accountingCode = $state('');
	let description = $state('');
	let expenseDate = $state<CalendarDate | undefined>(undefined);
	let totalMinor = $state(0);
	let reimburseTo = $state('');
	let saving = $state(false);
	let error = $state('');
	let receipts: AttachmentsCard | undefined = $state();

	// The crew list feeds the "reimburse to" picker. Worth fetching only while the dialog is open.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: open,
		staleTime: 5 * 60 * 1000
	}));
	const team = $derived<TeamMember[]>(teamQuery.data ?? []);
	const reimburseOptions = $derived([
		{ value: '', label: 'Not reimbursable' },
		...team.map((member) => ({ value: member.id, label: member.full_name ?? 'A team member' }))
	]);

	// Read the expense into the form each time the dialog opens, never while it is open, so typing is never
	// overwritten by a background refetch.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			if (expense) {
				name = expense.name;
				accountingCode = expense.accounting_code ?? '';
				description = expense.description ?? '';
				expenseDate = calendarDateFromString(expense.expense_date);
				totalMinor = expense.total_minor ?? 0;
				reimburseTo = expense.reimburse_to_user_id ?? '';
			} else {
				name = '';
				accountingCode = '';
				description = '';
				expenseDate = calendarDateFromString(new Date().toISOString());
				totalMinor = 0;
				reimburseTo = '';
			}
			error = '';
		}
		wasOpen = open;
	});

	function closeIfIdle() {
		if (saving) return;
		onClose();
	}

	async function submit() {
		if (saving) return;
		error = '';
		const trimmedName = name.trim();
		if (trimmedName.length < 2) {
			error = 'Give this expense a name.';
			return;
		}
		const dateString = calendarDateToString(expenseDate);
		if (!dateString) {
			error = 'Choose the date of this expense.';
			return;
		}

		saving = true;
		try {
			const id = await writeExpense({
				name: trimmedName,
				accounting_code: accountingCode.trim() || null,
				description: description.trim() || null,
				expense_date: dateString,
				total_minor: totalMinor,
				reimburse_to_user_id: reimburseTo || null
			});

			// The receipt files wait for exactly this moment: the expense now has an id to hang off. saveAll
			// uploads the picked files and removes any staged for deletion, and reports how many failed.
			const failures = (await receipts?.saveAll(id)) ?? 0;
			onSaved(
				failures > 0
					? expense
						? 'Expense saved, but a receipt could not be uploaded.'
						: 'Expense recorded, but a receipt could not be uploaded.'
					: expense
						? 'Expense saved'
						: 'Expense recorded'
			);
		} catch (cause) {
			const failure = cause as JobWriteError;
			error = failure.fieldErrors?.form ?? failure.message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title={expense ? 'Edit expense' : 'New expense'} size="small" onClose={closeIfIdle}>
	<div class="expense-dialog">
		{#if error}<p class="expense-dialog__alert" role="alert">{error}</p>{/if}

		<div class="expense-dialog__row">
			<Input id="expense-name" label="Item name" maxlength={160} bind:value={name} />
			<Input
				id="expense-code"
				label="Accounting code (optional)"
				maxlength={64}
				bind:value={accountingCode}
			/>
		</div>

		<Textarea
			id="expense-description"
			label="Description (optional)"
			rows={3}
			maxlength={2000}
			bind:value={description}
		/>

		<div class="expense-dialog__row">
			<CalendarPicker id="expense-date" label="Date" {locale} bind:value={expenseDate} />
			<MoneyInput id="expense-total" label={`Total (${currencyCode})`} bind:value={totalMinor} />
		</div>

		<Select
			id="expense-reimburse"
			label="Reimburse to"
			placeholder={teamQuery.isPending ? 'Loading your team…' : 'Not reimbursable'}
			options={reimburseOptions}
			disabled={!canManageTeam && !expense}
			bind:value={reimburseTo}
		/>

		<AttachmentsCard
			bind:this={receipts}
			entityType="job_expense"
			entityId={expense?.id}
			{currentUserId}
			title="Receipt"
			surface="section"
		/>

		<div class="expense-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={closeIfIdle}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={submit}>
				{expense ? 'Save expense' : 'Record expense'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.expense-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__row {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
