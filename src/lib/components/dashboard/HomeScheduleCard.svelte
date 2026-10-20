<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { resolve } from '$app/paths';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import squareCheckIcon from '@tabler/icons/outline/square-check.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { clockSentence, type HomeSchedule, type HomeScheduleRow } from '$lib/home/schedule';
	import type { TeamMember } from '$lib/team/api';

	// Today's schedule: how the day stands (completed, still to do, late) above the day's work in time order,
	// anytime work last, and the work left over from earlier days at the foot. "By visit" lists the work;
	// "By person" shows each teammate's share of it. Statuses are the Schedule's own; see `$lib/home/schedule`.
	let {
		schedule,
		team = [],
		loading = false,
		failed = false,
		onretry
	}: {
		schedule: HomeSchedule | undefined;
		team?: TeamMember[];
		loading?: boolean;
		failed?: boolean;
		onretry?: () => void;
	} = $props();

	let view = $state<'visit' | 'person'>('visit');
	const uid = $props.id();

	const membersById = $derived(new Map(team.map((member) => [member.id, member])));
	const counts = $derived(schedule?.counts);

	// The quiet line under the title: how much is on, then who is out, when the day ends and what has no one.
	const hint = $derived.by(() => {
		if (!schedule) return null;
		const { total, unassigned } = schedule.counts;
		const parts = [
			total === 0 ? 'Nothing booked today' : `${total} ${total === 1 ? 'item' : 'items'}`
		];
		if (schedule.peopleOut > 0)
			parts.push(`${schedule.peopleOut} ${schedule.peopleOut === 1 ? 'person' : 'people'} out`);
		if (schedule.lastEndMinutes !== null)
			parts.push(`last one ends ${clockSentence(schedule.lastEndMinutes)}`);
		if (unassigned > 0) parts.push(`${unassigned} unassigned`);
		return parts.join(' · ');
	});

	const tiles = $derived(
		counts
			? [
					{ key: 'completed', label: 'Completed', count: counts.completed },
					{ key: 'todo', label: 'Still to do', count: counts.todo },
					{ key: 'late', label: 'Late', count: counts.late }
				]
			: []
	);

	function nameOf(id: string | null) {
		if (id === null) return 'Unassigned';
		return membersById.get(id)?.full_name ?? 'Team member';
	}

	function rowHref(row: HomeScheduleRow) {
		if (row.route.page === 'job') return resolve('/(app)/jobs/[id=uuid]', { id: row.route.id });
		if (row.route.page === 'request')
			return resolve('/(app)/requests/[id=uuid]', { id: row.route.id });
		return resolve('/(app)/pipeline');
	}

	const kindLook = {
		visit: { tone: 'job', icon: hammerIcon },
		assessment: { tone: 'request', icon: clipboardListIcon },
		task: { tone: 'task', icon: squareCheckIcon }
	} as const;
	const statusLabel = { completed: 'Completed', todo: 'Still to do', late: 'Late' } as const;
	const statusTone = { completed: 'success', todo: 'inactive', late: 'critical' } as const;
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
{#snippet row(item: HomeScheduleRow)}
	<li>
		<a
			class="home-row"
			href={rowHref(item)}
			aria-label={`${item.timeTop} ${item.timeBottom}, ${item.title}, ${statusLabel[item.status]}`}
		>
			<span class="home-row__time">
				<span class="home-row__time-top">{item.timeTop}</span>
				{#if item.timeBottom}<span class="home-row__time-bottom">{item.timeBottom}</span>{/if}
			</span>
			<IconTile icon={kindLook[item.kind].icon} tone={kindLook[item.kind].tone} size={32} />
			<span class="home-row__main">
				<span class="home-row__title">{item.work}</span>
				<span class="home-row__meta">
					{[item.client, item.place, item.length].filter(Boolean).join(' · ') ||
						'No address to show'}
				</span>
			</span>
			<span class="home-row__people">
				{#if item.assigneeIds.length === 0 && item.status !== 'completed'}
					<span class="home-row__assign">
						<span class="home-row__assign-icon" aria-hidden="true">{@html userPlusIcon}</span>Assign
					</span>
				{:else}
					{#each item.assigneeIds.slice(0, 2) as id (id)}
						<span class="home-row__avatar" title={nameOf(id)}>
							<Avatar {id} name={nameOf(id)} src={membersById.get(id)?.avatar_url} size="small" />
						</span>
					{/each}
					{#if item.assigneeIds.length > 2}
						<span class="home-row__more">+{item.assigneeIds.length - 2}</span>
					{/if}
				{/if}
			</span>
			<span class="home-row__status">
				<StatusBadge status={statusTone[item.status]} size="small"
					>{statusLabel[item.status]}</StatusBadge
				>
			</span>
		</a>
	</li>
{/snippet}

<section class="home-schedule" aria-labelledby="{uid}-title" aria-busy={loading}>
	<CardHeader id="{uid}-title" title="Today’s schedule" {hint} icon={calendarIcon} tone="time">
		{#snippet actions()}
			<SegmentedControl
				ariaLabel="Group today's schedule"
				size="small"
				tone="plain"
				bind:value={view}
				options={[
					{ value: 'visit', label: 'By visit' },
					{ value: 'person', label: 'By person' }
				]}
			/>
			<Button variant="secondary" iconOnly label="Open schedule" href={resolve('/(app)/schedule')}>
				{@html arrowUpRightIcon}
			</Button>
		{/snippet}
	</CardHeader>

	{#if loading}
		<HomeCardState state="loading" label="today’s schedule" rows={4} />
	{:else if failed || !schedule}
		<HomeCardState state="error" label="today’s schedule" {onretry} />
	{:else if schedule.counts.total === 0 && schedule.late.length === 0}
		<HomeCardState
			state="empty"
			label="today’s schedule"
			title="Nothing booked for today"
			description="Visits, assessments and tasks dated today will show here."
			icon={calendarIcon}
		/>
	{:else}
		<div class="home-schedule__body">
			<ul class="home-schedule__tiles" aria-label="How today stands">
				{#each tiles as tile (tile.key)}
					<li class="home-schedule__tile home-schedule__tile--{tile.key}">
						<strong>{tile.count}</strong>{tile.label}
					</li>
				{/each}
			</ul>

			{#if view === 'visit'}
				{#if schedule.today.length === 0}
					<p class="home-schedule__quiet">Nothing else is booked for today.</p>
				{:else}
					<ul class="home-schedule__rows">
						{#each schedule.today as item (item.key)}{@render row(item)}{/each}
					</ul>
				{/if}
				{#if schedule.late.length > 0}
					<p class="home-schedule__band">
						<span class="home-schedule__band-icon" aria-hidden="true"
							>{@html alertTriangleIcon}</span
						>
						Late from earlier days
					</p>
					<ul class="home-schedule__rows home-schedule__rows--late">
						{#each schedule.late as item (item.key)}{@render row(item)}{/each}
					</ul>
				{/if}
			{:else if schedule.byPerson.length === 0}
				<p class="home-schedule__quiet">Nobody has work booked for today.</p>
			{:else}
				<ul class="home-people">
					{#each schedule.byPerson as person (person.id ?? 'none')}
						<li class="home-people__row">
							{#if person.id}
								<Avatar
									id={person.id}
									name={nameOf(person.id)}
									src={membersById.get(person.id)?.avatar_url}
									size="medium"
								/>
							{:else}
								<span class="home-people__open" aria-hidden="true">{@html userPlusIcon}</span>
							{/if}
							<div class="home-people__text">
								<strong>{nameOf(person.id)}</strong>
								<div
									class="home-people__track"
									role="img"
									aria-label={`${person.done} of ${person.total} done`}
								>
									<span style:width={`${(person.done / person.total) * 100}%`}></span>
								</div>
							</div>
							<span class="home-people__count">{person.done} of {person.total} done</span>
						</li>
					{/each}
				</ul>
			{/if}
		</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.home-schedule {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__body {
			display: grid;
			gap: var(--space-base);
			padding: var(--space-medium);
		}

		&__tiles {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__tile {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: 10px var(--space-slim);
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;

			strong {
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
				font-variant-numeric: tabular-nums;
			}
			&--completed {
				color: var(--color-success--onSurface);
				background: var(--color-success--surface);
			}
			&--todo {
				color: var(--color-inactive--onSurface);
				background: var(--color-inactive--surface);
			}
			&--late {
				color: var(--color-critical--onSurface);
				background: var(--color-critical--surface);
			}
		}

		&__rows {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;

			> li + li {
				border-top: var(--border-base) solid var(--color-border);
			}
			&--late {
				border: var(--border-base) solid var(--color-critical--surface);
				border-radius: var(--radius-base);
			}
		}

		&__band {
			display: flex;
			align-items: center;
			gap: 6px;
			padding: var(--space-smaller) var(--space-small) 0;
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}
		&__band-icon {
			display: inline-flex;
			color: var(--color-critical);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__quiet {
			padding: var(--space-slim) var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}
	}

	.home-row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: var(--space-slim) var(--space-small);
		border-radius: var(--radius-base);
		color: inherit;
		text-decoration: none;
		transition: background var(--timing-quick) ease;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&__time {
			display: grid;
			flex: 0 0 64px;
		}
		&__time-top {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
		&__time-bottom {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__main {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;
		}
		&__title {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__meta {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__people {
			display: flex;
			flex: 0 0 72px;
			align-items: center;
			justify-content: flex-start;
		}
		&__avatar {
			display: inline-flex;
			border-radius: var(--radius-circle);
			box-shadow: 0 0 0 2px var(--color-surface);

			/* People wear the one person colour here, not a colour each. */
			:global(.avatar) {
				width: 28px;
				height: 28px;
				color: var(--color-client--onSurface);
				background: var(--color-client--surface);
				font-size: var(--typography--fontSize-overline);
				font-weight: 700;
			}

			& + & {
				margin-left: -6px;
			}
		}
		&__more {
			margin-left: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__assign {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__assign-icon {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__status {
			display: flex;
			flex: 0 0 104px;
			justify-content: flex-end;
		}
	}

	.home-people {
		display: grid;
		margin: 0;
		padding: 0;
		list-style: none;

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-slim) var(--space-small);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
		&__text {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: var(--space-small);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}
		&__track {
			height: 6px;
			overflow: hidden;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background--subtle);

			span {
				display: block;
				height: 100%;
				border-radius: var(--radius-circle);
				background: var(--color-success);
			}
		}
		&__count {
			flex: 0 0 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
		&__open {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 40px;
			height: 40px;
			border-radius: var(--radius-circle);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}

	@media (max-width: 760px) {
		.home-row {
			flex-wrap: wrap;

			&__people,
			&__status {
				flex-basis: auto;
			}
		}
		.home-schedule__tiles {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
