<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import TaskDialog from './TaskDialog.svelte';
	import {
		deleteTask,
		fetchOpportunityTasks,
		invalidatePipeline,
		opportunityTasksKey,
		setTaskCompletion,
		type Task
	} from '$lib/pipeline/api';
	import { followUp, type BoardFormatting } from '$lib/pipeline/money';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';

	// The Brief's Tasks block: Jobber's five-open/five-completed list, with create, edit, delete, complete
	// and reopen. The card shows only the earliest one of these — this is where the rest live. The parent
	// keys this component by `opportunity.id`, so switching cards remounts it and resets any open dialog.
	let {
		opportunityId,
		formatting,
		canEdit
	}: {
		opportunityId: string;
		formatting: BoardFormatting | null;
		canEdit: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const tasksQuery = createQuery(() => ({
		queryKey: opportunityTasksKey(opportunityId),
		queryFn: () => fetchOpportunityTasks(opportunityId)
	}));
	const openTasks = $derived(tasksQuery.data?.open ?? []);
	const completedTasks = $derived(tasksQuery.data?.completed ?? []);

	// The Salesperson filter and `OpportunityOwnerField` already keep this warm on most visits to the
	// board, so resolving a Task's assignee to a name here almost never costs its own request.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 300_000
	}));
	function assignee(task: Task) {
		if (!task.assignee_user_id) return null;
		return teamQuery.data?.find((member) => member.id === task.assignee_user_id) ?? null;
	}

	function dueInfo(task: Task) {
		if (!formatting || !task.due_on) return null;
		const chase = followUp(task.due_on, formatting);
		return chase ? { label: chase.label, overdue: chase.overdue } : null;
	}

	let dialogOpen = $state(false);
	let editingTask = $state<Task | null>(null);
	let deletingTask = $state<Task | null>(null);

	function openCreate() {
		editingTask = null;
		dialogOpen = true;
	}
	function openEdit(task: Task) {
		editingTask = task;
		dialogOpen = true;
	}
	function handleSaved() {
		invalidatePipeline(queryClient);
		dialogOpen = false;
	}

	// A Task write can change which Task is earliest-due, so it can change what the card behind this
	// drawer shows — every write here clears the whole `['pipeline']` family, not just this Brief's own
	// list, the same way an owner or value edit already does.
	const completionMutation = createMutation(() => ({
		mutationFn: (input: { task: Task; completed: boolean }) =>
			setTaskCompletion(input.task.id, input.completed),
		onSuccess: () => invalidatePipeline(queryClient),
		onError: (error: Error) => toast.error('Could not update the task', error.message)
	}));

	const deleteMutation = createMutation(() => ({
		mutationFn: (task: Task) => deleteTask(task.id),
		onSuccess: () => {
			invalidatePipeline(queryClient);
			deletingTask = null;
		},
		onError: (error: Error) => {
			toast.error('Could not delete the task', error.message);
			deletingTask = null;
		}
	}));

	function menuItems(task: Task) {
		return [
			{ label: 'Edit', onSelect: () => openEdit(task) },
			{ label: 'Delete', destructive: true, onSelect: () => (deletingTask = task) }
		];
	}
</script>

<section class="tasks" aria-labelledby="brief-tasks-heading">
	<div class="tasks__header">
		<h3 id="brief-tasks-heading" class="tasks__heading">
			Tasks
			{#if tasksQuery.data}<span class="tasks__count">{openTasks.length}/5</span>{/if}
		</h3>
		{#if canEdit}
			<Button size="small" variant="tertiary" disabled={openTasks.length >= 5} onclick={openCreate}>
				+ Add task
			</Button>
		{/if}
	</div>

	{#if tasksQuery.isPending}
		<p class="tasks__state">Loading tasks…</p>
	{:else if tasksQuery.isError}
		<p class="tasks__state tasks__state--error">The tasks could not be loaded.</p>
	{:else if openTasks.length === 0 && completedTasks.length === 0}
		<p class="tasks__state">No tasks yet</p>
	{:else}
		{#if openTasks.length > 0}
			<ul class="tasks__list">
				{#each openTasks as task (task.id)}
					{@const due = dueInfo(task)}
					{@const owner = assignee(task)}
					<li class="tasks__row">
						<Checkbox
							id={`task-${task.id}-complete`}
							label={`Mark "${task.title}" complete`}
							checked={false}
							disabled={!canEdit || completionMutation.isPending}
							onchange={() => completionMutation.mutate({ task, completed: true })}
						/>
						<span class="tasks__body">
							<span class="tasks__title">{task.title}</span>
							{#if due}
								<span class="tasks__due" class:tasks__due--overdue={due.overdue}>
									{due.overdue ? 'Overdue' : 'Due'}
									{due.label}
								</span>
							{/if}
						</span>
						{#if owner}
							<Avatar id={owner.id} name={owner.full_name} src={owner.avatar_url} size="small" />
						{/if}
						{#if canEdit}
							<DropdownMenu
								items={menuItems(task)}
								triggerLabel={`Task actions for ${task.title}`}
							/>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if completedTasks.length > 0}
			<h4 class="tasks__subheading">COMPLETED · {completedTasks.length}</h4>
			<ul class="tasks__list">
				{#each completedTasks as task (task.id)}
					{@const owner = assignee(task)}
					<li class="tasks__row tasks__row--completed">
						<Checkbox
							id={`task-${task.id}-complete`}
							label={`Reopen "${task.title}"`}
							checked={true}
							disabled={!canEdit || completionMutation.isPending}
							onchange={() => completionMutation.mutate({ task, completed: false })}
						/>
						<span class="tasks__body">
							<span class="tasks__title tasks__title--done">{task.title}</span>
						</span>
						{#if owner}
							<Avatar id={owner.id} name={owner.full_name} src={owner.avatar_url} size="small" />
						{/if}
						{#if canEdit}
							<DropdownMenu
								items={menuItems(task)}
								triggerLabel={`Task actions for ${task.title}`}
							/>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</section>

{#if dialogOpen}
	<TaskDialog
		open={dialogOpen}
		{opportunityId}
		task={editingTask}
		onSaved={handleSaved}
		onClose={() => (dialogOpen = false)}
	/>
{/if}

{#if deletingTask}
	{@const task = deletingTask}
	<ConfirmDialog
		open
		title="Delete this task?"
		tone="critical"
		confirmLabel="Delete task"
		destructive
		loading={deleteMutation.isPending}
		onConfirm={() => deleteMutation.mutate(task)}
		onClose={() => (deletingTask = null)}
	>
		<p>“{task.title}” will be removed. This cannot be undone.</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.tasks {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.tasks__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.tasks__heading {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.tasks__count {
		padding: 2px var(--space-smaller);
		border-radius: var(--radius-large);
		color: var(--color-text--secondary);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		text-transform: none;
		letter-spacing: normal;
	}
	.tasks__state {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			color: var(--color-critical);
		}
	}
	.tasks__subheading {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.tasks__list {
		display: flex;
		flex-direction: column;
	}
	.tasks__row {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-small) 0;
		border-bottom: var(--border-base) solid var(--color-border);

		&:last-child {
			border-bottom: 0;
		}
		&--completed {
			opacity: 0.75;
		}
	}
	.tasks__body {
		display: flex;
		min-width: 0;
		flex: 1 1 auto;
		flex-direction: column;
		gap: 2px;
		padding-top: 2px;
	}
	.tasks__title {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-tight);

		&--done {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}
	}
	.tasks__due {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--overdue {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}
	}
</style>
