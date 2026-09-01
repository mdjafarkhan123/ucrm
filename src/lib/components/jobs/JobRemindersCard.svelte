<script lang="ts">
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		addJobReminder,
		dismissJobReminder,
		deleteJobReminder,
		type JobInvoiceReminder,
		type JobWriteError
	} from '$lib/jobs/api';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// Invoice reminders are internal to-dos for our own team, never messages to the client — the card says
	// so in those words. A due reminder is what puts the job in "Requires invoicing"; clearing it means
	// invoicing (once Invoices exist) or, for a manual one, marking it invoiced here or deleting a mistake.
	// The month-end reminder seeds itself from the billing choice, so it can only be marked invoiced, never
	// deleted; a custom date a person typed can be deleted outright.
	let {
		jobId,
		reminders,
		today,
		locale = 'en-US',
		editable = false,
		onChanged
	}: {
		jobId: string;
		reminders: JobInvoiceReminder[];
		/** The organisation's own calendar day, YYYY-MM-DD, so due state matches the derived status. */
		today: string;
		locale?: string;
		editable?: boolean;
		onChanged: () => Promise<void> | void;
	} = $props();

	const toast = getToastManager();

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);

	const KIND_LABEL: Record<JobInvoiceReminder['reminder_kind'], string> = {
		monthly_last_day: 'Month end',
		custom_date: 'Custom date',
		on_completion: 'On completion',
		per_visit: 'Per visit'
	};

	// A YYYY-MM-DD string read at local noon, so the formatted date can never slip a day across a timezone.
	function formatDue(dueOn: string) {
		return dateFormat.format(new Date(`${dueOn}T12:00:00`));
	}

	// Due state against the organisation's clock, not the browser's — string compare is exact for
	// YYYY-MM-DD. Whole-day difference for the "in N days" hint uses UTC midnights so DST cannot shift it.
	function dueState(dueOn: string): { tone: 'overdue' | 'today' | 'upcoming'; label: string } {
		if (dueOn < today) return { tone: 'overdue', label: 'Overdue' };
		if (dueOn === today) return { tone: 'today', label: 'Due today' };
		const days = Math.round(
			(Date.parse(`${dueOn}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86_400_000
		);
		return { tone: 'upcoming', label: days === 1 ? 'Due tomorrow' : `Due in ${days} days` };
	}

	// --- Add a custom-date reminder ---------------------------------------------------------------------
	let addOpen = $state(false);
	let draftDate = $state('');
	let draftNote = $state('');
	let saving = $state(false);
	let addError = $state('');

	const todayValue = $derived(calendarDateFromString(today));

	function openAdd() {
		draftDate = '';
		draftNote = '';
		addError = '';
		addOpen = true;
	}

	function closeAdd() {
		if (saving) return;
		addOpen = false;
	}

	async function saveReminder() {
		if (saving || !draftDate) return;
		saving = true;
		addError = '';
		try {
			await addJobReminder(jobId, draftDate, draftNote.trim() || null);
			addOpen = false;
			await onChanged();
			toast.success('Reminder added');
		} catch (cause) {
			const failure = cause as JobWriteError;
			addError = failure.fieldErrors?.form ?? failure.message;
		} finally {
			saving = false;
		}
	}

	// --- Mark invoiced (dismiss) ------------------------------------------------------------------------
	// Kept as history rather than deleted, so an office can prove a job was billed outside the system. Not
	// destructive, so it fires straight from the row menu without a confirm.
	let busyId = $state('');

	async function markInvoiced(reminder: JobInvoiceReminder) {
		if (busyId) return;
		busyId = reminder.id;
		try {
			await dismissJobReminder(jobId, reminder.id);
			await onChanged();
			toast.success('Marked as invoiced');
		} catch (cause) {
			toast.error((cause as JobWriteError).message ?? 'That reminder could not be updated.');
		} finally {
			busyId = '';
		}
	}

	// --- Delete a mistaken custom date ------------------------------------------------------------------
	let confirmDelete = $state<JobInvoiceReminder | null>(null);

	async function reallyDelete() {
		const reminder = confirmDelete;
		if (!reminder || busyId) return;
		busyId = reminder.id;
		try {
			await deleteJobReminder(jobId, reminder.id);
			confirmDelete = null;
			await onChanged();
			toast.success('Reminder deleted');
		} catch (cause) {
			toast.error((cause as JobWriteError).message ?? 'That reminder could not be deleted.');
		} finally {
			busyId = '';
		}
	}

	type MenuItem = { label: string; icon: string; onSelect: () => void; destructive?: boolean };

	function menuItems(reminder: JobInvoiceReminder): MenuItem[] {
		const items: MenuItem[] = [
			{ label: 'Mark as invoiced', icon: checkIcon, onSelect: () => void markInvoiced(reminder) }
		];
		if (reminder.reminder_kind === 'custom_date') {
			items.push({
				label: 'Delete reminder',
				icon: trashIcon,
				onSelect: () => (confirmDelete = reminder),
				destructive: true
			});
		}
		return items;
	}
</script>

<RailCard title="Invoice reminders" icon={bellIcon} count={reminders.length}>
	{#snippet actions()}
		{#if editable}
			<Button variant="tertiary" size="small" onclick={openAdd}>Add</Button>
		{/if}
	{/snippet}

	{#if reminders.length === 0}
		<p class="job-reminders__empty">
			Nothing to invoice yet. A due reminder is what flags this job as needing an invoice.
		</p>
	{:else}
		<ul class="job-reminders">
			{#each reminders as reminder (reminder.id)}
				{@const due = dueState(reminder.due_on)}
				<li class="job-reminders__item" class:job-reminders__item--busy={busyId === reminder.id}>
					<div class="job-reminders__body">
						<p class="job-reminders__date">
							{formatDue(reminder.due_on)}
							<span class="job-reminders__due job-reminders__due--{due.tone}">{due.label}</span>
						</p>
						<p class="job-reminders__kind">{KIND_LABEL[reminder.reminder_kind]}</p>
						{#if reminder.note}<p class="job-reminders__note">{reminder.note}</p>{/if}
					</div>
					{#if editable}
						<DropdownMenu
							items={menuItems(reminder)}
							triggerLabel="Reminder actions"
							disabled={busyId === reminder.id}
						/>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	<p class="job-reminders__hint">
		Reminders are prompts for your own team, not messages to the client.
	</p>
</RailCard>

{#if addOpen}
	<Dialog open={addOpen} title="Add an invoice reminder" size="small" onClose={closeAdd}>
		<div class="job-reminders-dialog">
			{#if addError}<p class="job-reminders-dialog__error" role="alert">{addError}</p>{/if}

			<CalendarPicker
				id="job-reminder-date"
				label="Remind our team on"
				minValue={todayValue}
				value={calendarDateFromString(draftDate)}
				onchange={(value) => (draftDate = calendarDateToString(value))}
				{locale}
			/>

			<Input
				id="job-reminder-note"
				label="Note (optional)"
				placeholder="e.g. bill with the March statement"
				maxlength={200}
				bind:value={draftNote}
			/>

			<p class="job-reminders-dialog__hint">
				This is a reminder for your own team on the date you pick — nothing is sent to the client.
			</p>

			<div class="job-reminders-dialog__actions">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={closeAdd}>
					Cancel
				</Button>
				<Button variant="primary" loading={saving} disabled={!draftDate} onclick={saveReminder}>
					Add reminder
				</Button>
			</div>
		</div>
	</Dialog>
{/if}

<ConfirmDialog
	open={confirmDelete !== null}
	title="Delete this reminder?"
	confirmLabel="Delete reminder"
	destructive
	loading={busyId !== '' && busyId === confirmDelete?.id}
	onConfirm={() => void reallyDelete()}
	onClose={() => {
		if (!busyId) confirmDelete = null;
	}}
>
	This removes the reminder for good. To keep a record that the job was billed, mark it as invoiced
	instead.
</ConfirmDialog>

<style lang="scss">
	.job-reminders {
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
			gap: var(--space-small);

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

		&__date {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__due {
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&--overdue {
				color: var(--color-destructive);
			}
			&--today {
				color: var(--color-warning);
			}
			&--upcoming {
				color: var(--color-text--secondary);
				font-weight: 400;
			}
		}

		&__kind {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}
	}

	.job-reminders__empty {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.job-reminders__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.job-reminders-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
