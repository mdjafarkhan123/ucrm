<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { invalidatePipeline, setTaskCompletion } from '$lib/pipeline/api';
	import { visitDerivedStatus } from '$lib/schedule/status';
	import { assignmentLabel } from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { TaskItem } from '$lib/schedule/items';
	import type { TeamMember } from '$lib/team/api';
	import squareIcon from '@tabler/icons/outline/square.svg?raw';
	import squareCheckIcon from '@tabler/icons/outline/square-check.svg?raw';

	// One Pipeline Task on its assignee's day (Pipeline E1).
	//
	// It mirrors the other cards' shape so a day reads as one calendar, but the Pipeline owns it: the card is a
	// link, never a drag handle, and it opens the card's Brief on the Pipeline, where the Task is edited. A
	// Task has a day and no time, so it only ever sits in Anytime. Its marker is an empty or ticked box and its
	// tag says "Task", so colour alone never carries the difference.
	//
	// The box is the one thing the calendar does to a Task: ticking it here is the same as ticking it in the
	// Brief (Jobber's calendar does the same). The title is the link and stretches over the whole card, with
	// the box sitting above it, so the card stays one click target without a button inside a link.

	let {
		task,
		density,
		today,
		employeesById,
		showAssignment = true
	}: {
		task: TaskItem;
		density: CardDensity;
		today: string;
		employeesById: Map<string, TeamMember>;
		/** False where the surface itself already says whose it is, as the Day board's employee row does. */
		showAssignment?: boolean;
	} = $props();

	const status = $derived(visitDerivedStatus(task, today));
	const done = $derived(status === 'completed');
	const overdue = $derived(status === 'late');

	const clientLabel = $derived(task.client_name ?? task.client_company_name ?? null);
	const titleLabel = $derived(task.title.trim() || 'Task');

	// An open card opens its Brief on the board. A card that has been won, lost or closed is no longer on the
	// board, so its Task leads to the Quote or Request behind it instead.
	const href = $derived.by((): string => {
		if (!task.opportunity_open && task.quote_id)
			return resolve('/(app)/quotes/[id=uuid]', { id: task.quote_id });
		if (!task.opportunity_open && task.request_id)
			return resolve('/(app)/requests/[id=uuid]', { id: task.request_id });
		return `${resolve('/(app)/pipeline')}?brief=${task.opportunity_id}`;
	});

	// Whoever may edit the Pipeline may tick a Task off. Unticking starts the work again, which a card that
	// has left the board refuses, so a finished Task on a closed card keeps a plain marker.
	const canToggle = $derived(task.can_complete && (!done || task.opportunity_open));
	const toggleLabel = $derived(done ? `Reopen "${titleLabel}"` : `Mark "${titleLabel}" complete`);

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// A Task write can change which Task its card shows on the board, so this clears the Pipeline's caches
	// along with the calendar window, the same as the Brief's own tick.
	const completionMutation = createMutation(() => ({
		mutationFn: (completed: boolean) => setTaskCompletion(task.id, completed),
		onSuccess: (_result, completed) => {
			invalidatePipeline(queryClient);
			toast.success(completed ? 'Task completed' : 'Task reopened');
		},
		onError: (error: Error) => toast.error('Could not update the task', error.message)
	}));

	const summary = $derived(
		[
			'Task',
			titleLabel,
			clientLabel,
			assignmentLabel(task.assignee_ids, employeesById),
			done ? 'Completed' : overdue ? 'Late' : null
		]
			.filter(Boolean)
			.join(', ')
	);
</script>

<!-- The href is built with resolve() above; only the Brief's query string is added to it. -->
<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<div
	class="task-card task-card--{density}"
	class:task-card--done={done}
	class:task-card--overdue={overdue}
	class:task-card--saving={completionMutation.isPending}
	title={summary}
>
	<span class="task-card__line">
		{#if canToggle}
			<button
				type="button"
				class="task-card__tick"
				aria-busy={completionMutation.isPending}
				aria-label={toggleLabel}
				aria-pressed={done}
				disabled={completionMutation.isPending}
				onclick={() => completionMutation.mutate(!done)}
			>
				{#if completionMutation.isPending}<span class="task-card__spinner" aria-hidden="true"
					></span>{:else}{@html done ? squareCheckIcon : squareIcon}{/if}
			</button>
		{:else}
			<span class="task-card__marker" aria-hidden="true">
				{@html done ? squareCheckIcon : squareIcon}
			</span>
		{/if}
		<a {href} class="task-card__title" aria-label={summary}>{titleLabel}</a>
	</span>

	{#if density === 'compact' || density === 'standard'}
		{#if clientLabel}
			<span class="task-card__client">{clientLabel}</span>
		{/if}

		{#if density === 'standard'}
			<span class="task-card__foot">
				{#if showAssignment}
					<span class="task-card__assignment">
						{assignmentLabel(task.assignee_ids, employeesById)}
					</span>
				{/if}
				<span class="task-card__tag">{done ? 'Completed' : overdue ? 'Late' : 'Task'}</span>
			</span>
		{/if}
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.task-card__spinner {
		width: 13px;
		height: 13px;
		box-sizing: border-box;
		border: 2px solid var(--color-border);
		border-top-color: var(--color-task);
		border-radius: var(--radius-circle);
		animation: task-card-spin 0.8s linear infinite;
	}
	@keyframes task-card-spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.task-card__spinner {
			animation: none;
		}
	}
	.task-card--done .task-card__tag {
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}

	.task-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: 7px var(--space-small) var(--space-small) 9px;
		overflow: hidden;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		background-color: var(--color-task--surface);
		color: var(--color-text);
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover {
			border-color: var(--color-task);
			box-shadow: 0 4px 12px color-mix(in srgb, var(--color-heading) 12%, transparent);
		}
		// The link fills the card, so its focus ring is drawn on the card.
		&:has(.task-card__title:focus-visible) {
			box-shadow: var(--shadow-focus);
		}
	}

	.task-card--saving {
		opacity: 0.6;
	}

	.task-card--done {
		border-color: var(--color-border--interactive);
		background-color: var(--color-surface--active);
		color: var(--color-text--secondary);

		.task-card__title {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}
	}

	.task-card--overdue {
		border-left: 4px solid var(--color-critical);
	}

	.task-card__line {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.task-card__marker,
	.task-card__tick {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--color-task);

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	// Sits above the stretched link. Its padding makes the box easier to hit, and the matching negative
	// margin keeps the title exactly where the plain marker leaves it.
	.task-card__tick {
		position: relative;
		z-index: 1;
		margin: calc(-1 * var(--space-smaller));
		padding: var(--space-smaller);
		border: 0;
		border-radius: var(--radius-small);
		background: none;
		cursor: pointer;
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover:not(:disabled) {
			background-color: var(--color-task--surface);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			cursor: default;
		}
	}

	.task-card__title {
		flex: 1 1 auto;
		min-width: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		text-decoration: none;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;

		&:focus-visible {
			outline: none;
		}
		// Stretches the link over the whole card, so anywhere but the box opens the Task's card.
		&::after {
			content: '';
			position: absolute;
			inset: 0;
		}
	}

	.task-card__client,
	.task-card__assignment {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.task-card__foot {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		margin-top: auto;
		min-width: 0;
	}

	.task-card__tag {
		flex-shrink: 0;
		margin-left: auto;
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-small);
		background-color: var(--color-task--surface);
		color: var(--color-task--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-loose);
		white-space: nowrap;
	}

	.task-card--overdue .task-card__tag {
		background-color: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
	}

	.task-card--micro,
	.task-card--pill {
		justify-content: center;
		padding: 0 var(--space-small) 0 var(--space-slim);

		.task-card__title {
			color: var(--color-text);
			font-weight: 500;
		}
	}
</style>
