<script lang="ts">
	import { resolve } from '$app/paths';
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
	// link, never a drag handle, and it opens the card's Brief on the Pipeline, where the Task is edited and
	// ticked off. A Task has a day and no time, so it only ever sits in Anytime. Its marker is an empty or
	// ticked box and its tag says "Task", so colour alone never carries the difference.

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

	const summary = $derived(
		[
			'Task',
			titleLabel,
			clientLabel,
			assignmentLabel(task.assignee_ids, employeesById),
			done ? 'Done' : overdue ? 'Overdue' : null
		]
			.filter(Boolean)
			.join(', ')
	);
</script>

<!-- The href is built with resolve() above; only the Brief's query string is added to it. -->
<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<a
	{href}
	class="task-card task-card--{density}"
	class:task-card--done={done}
	class:task-card--overdue={overdue}
	aria-label={summary}
	title={summary}
>
	<span class="task-card__accent" aria-hidden="true"></span>

	{#if density === 'micro'}
		<span class="task-card__line">
			<span class="task-card__marker" aria-hidden="true">
				{@html done ? squareCheckIcon : squareIcon}
			</span>
			<span class="task-card__title">{titleLabel}</span>
		</span>
	{:else}
		<span class="task-card__line">
			<span class="task-card__marker" aria-hidden="true">
				{@html done ? squareCheckIcon : squareIcon}
			</span>
			<span class="task-card__title">{titleLabel}</span>
		</span>
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
				<span class="task-card__tag">{done ? 'Done' : overdue ? 'Overdue' : 'Task'}</span>
			</span>
		{/if}
	{/if}
</a>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.task-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: var(--space-smaller) var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		background-color: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.task-card__accent {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: var(--space-smaller);
		// The Task accent, so a follow-up reads as a different kind of item from a visit at a glance.
		background-color: var(--color-task);
	}

	.task-card--done {
		border-style: dashed;
		color: var(--color-text--secondary);

		.task-card__title {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}
		.task-card__accent {
			opacity: 0.5;
		}
	}

	.task-card--overdue {
		border-color: var(--color-critical);
	}

	.task-card__line {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.task-card__marker {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--color-task);

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.task-card__title {
		flex: 1 1 auto;
		min-width: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
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

	.task-card--micro {
		justify-content: center;
		padding: 0 var(--space-smaller) 0 var(--space-small);

		.task-card__title {
			color: var(--color-text);
			font-weight: 500;
		}
	}
</style>
