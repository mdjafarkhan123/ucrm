<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { CalendarDate, getLocalTimeZone, today } from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		createTask,
		updateTask,
		TaskWriteError,
		type Task,
		type TaskInput
	} from '$lib/pipeline/api';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';

	// Creates or edits one Brief Task. Owns the write itself, the same way `PropertyDialog` does for a
	// client's property: there is no page draft to stage into here, so Save writes straight away and the
	// caller only has to fold the result into its own cache.
	let {
		open,
		opportunityId = '',
		task = null,
		submit,
		bulkCount = 0,
		futureDueFor = null,
		timezone,
		onSaved,
		onClose
	}: {
		open: boolean;
		/** The one Opportunity the Task is for. Not needed when `submit` writes it instead. */
		opportunityId?: string;
		/** The Task being edited, or null to create a new one. */
		task?: Task | null;
		/** The on-hold stage a card is waiting to enter. Set, the due date becomes required and has to be
		 *  after today, because that is the Task the stage is asking for. */
		futureDueFor?: string | null;
		/** The organization's timezone, which decides what "today" is for that rule. */
		timezone?: string;
		/** Writes the new Task somewhere other than one Opportunity — the Table's bulk tools give every
		 *  selected card its own copy. The caller reports the result and closes the dialog; a thrown
		 *  refusal shows here, the same as a single Task's. */
		submit?: (input: TaskInput) => Promise<void>;
		/** How many cards `submit` is writing to, for the title. */
		bulkCount?: number;
		onSaved?: (task: Task) => void;
		onClose: () => void;
	} = $props();

	// The pickers speak CalendarDate; the database speaks `2026-08-19`, same conversion
	// `OpportunityDetailsSection` and `BoardControls` already use for their own date fields.
	function toCalendarDate(day: string | null | undefined) {
		if (!day) return undefined;
		const [year, month, date] = day.split('-').map(Number);
		return new CalendarDate(year, month, date);
	}
	function toDay(value: CalendarDate | undefined) {
		if (!value) return null;
		return `${value.year}-${String(value.month).padStart(2, '0')}-${String(value.day).padStart(2, '0')}`;
	}

	type TaskDraft = {
		title: string;
		instructions: string;
		assignee_user_id: string;
		due_on: CalendarDate | undefined;
	};

	function draftFrom(source: Task | null): TaskDraft {
		return {
			title: source?.title ?? '',
			instructions: source?.instructions ?? '',
			assignee_user_id: source?.assignee_user_id ?? '',
			due_on: toCalendarDate(source?.due_on)
		};
	}

	// A one-time copy taken when the dialog mounts, so a background team-list refetch cannot overwrite
	// typing.
	let draft = $state<TaskDraft>(untrack(() => draftFrom(task)));
	let saving = $state(false);
	const toast = getToastManager();
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const isEdit = $derived(task !== null);
	// The first day an on-hold stage accepts: tomorrow, on the organization's own calendar.
	const earliestDue = $derived(
		futureDueFor === null ? undefined : today(timezone ?? getLocalTimeZone()).add({ days: 1 })
	);
	const dueIsLateEnough = $derived(
		earliestDue === undefined ||
			(draft.due_on !== undefined && draft.due_on.compare(earliestDue) >= 0)
	);
	const canSubmit = $derived(draft.title.trim().length >= 2 && dueIsLateEnough);

	// The Salesperson filter loads this same list as soon as the board renders, so this almost always
	// finds it already warm.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 300_000
	}));
	const teamOptions = $derived([
		{ value: '', label: 'Unassigned' },
		...(teamQuery.data ?? []).map((member) => ({
			value: member.id,
			label: member.full_name ?? 'Unnamed teammate'
		}))
	]);

	async function save() {
		if (!canSubmit || saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		const input: TaskInput = {
			title: draft.title.trim(),
			instructions: draft.instructions.trim() || null,
			assignee_user_id: draft.assignee_user_id || null,
			due_on: toDay(draft.due_on)
		};
		try {
			if (submit) {
				await submit(input);
				return;
			}
			const saved = task
				? await updateTask(task.id, input)
				: await createTask(opportunityId, input);
			toast.success(task ? 'Task saved' : 'Task added');
			onSaved?.(saved);
		} catch (thrown) {
			if (thrown instanceof TaskWriteError) {
				fieldErrors = thrown.fieldErrors;
				// A limit refusal or an ineligible-assignee refusal comes back as a sentence written for the
				// user under its own field — show it as-is rather than rewriting it.
				formError =
					fieldErrors.form ?? (Object.keys(fieldErrors).length === 0 ? thrown.message : '');
			} else {
				formError = thrown instanceof Error ? thrown.message : 'That task could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	{open}
	title={futureDueFor !== null
		? 'Add a follow-up task'
		: isEdit
			? 'Edit task'
			: submit
				? `Add a task to ${bulkCount} ${bulkCount === 1 ? 'card' : 'cards'}`
				: 'New task'}
	onClose={saving ? () => {} : onClose}
>
	<div class="task-dialog">
		{#if futureDueFor !== null}
			<p class="task-dialog__reason">
				Cards in “{futureDueFor}” need a task with a future due date, so nobody forgets to come back
				to them. Add one and the card will move.
			</p>
		{/if}
		{#if submit}
			<p class="task-dialog__reason">
				Each card gets its own copy of this task, so it can be finished on one card without the
				others.
			</p>
		{/if}
		<Input
			id="task-dialog-title"
			label="Title"
			required
			maxlength={160}
			bind:value={draft.title}
			invalid={Boolean(fieldErrors.title)}
			errorMessage={fieldErrors.title}
		/>
		<Textarea
			id="task-dialog-instructions"
			label="Instructions (optional)"
			rows={3}
			maxlength={2000}
			bind:value={draft.instructions}
			invalid={Boolean(fieldErrors.instructions)}
			errorMessage={fieldErrors.instructions}
		/>
		<div class="task-dialog__field">
			<label class="task-dialog__label" for="task-dialog-owner">Owner</label>
			<Select
				id="task-dialog-owner"
				bind:value={draft.assignee_user_id}
				options={teamOptions}
				placeholder="Unassigned"
			/>
			{#if fieldErrors.assignee_user_id}
				<p class="task-dialog__field-error" role="alert">{fieldErrors.assignee_user_id}</p>
			{/if}
		</div>
		<CalendarPicker
			id="task-dialog-due"
			label="Due date"
			value={draft.due_on}
			required={futureDueFor !== null}
			minValue={earliestDue}
			invalid={Boolean(fieldErrors.due_on) || (draft.due_on !== undefined && !dueIsLateEnough)}
			errorMessage={fieldErrors.due_on ??
				(draft.due_on !== undefined && !dueIsLateEnough ? 'Pick a day after today.' : '')}
			onchange={(value) => (draft.due_on = value)}
		/>

		{#if formError}<p class="task-dialog__error" role="alert">{formError}</p>{/if}

		<div class="task-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" disabled={!canSubmit} loading={saving} onclick={() => void save()}>
				{futureDueFor !== null ? 'Add task and move card' : isEdit ? 'Save' : 'Add task'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.task-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}
		&__reason {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__field-error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
