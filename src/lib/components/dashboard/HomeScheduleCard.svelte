<script lang="ts">
	import { resolve } from '$app/paths';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import calendarEventIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import { clockSentence, type HomeSchedule, type HomeScheduleRow } from '$lib/home/schedule';
	import type { TeamMember } from '$lib/team/api';

	// Today's schedule: a dark summary of the day (how much is on, how much is done, what needs a look) above
	// the day's work, late items first. "By visit" lists the work in time order; "By person" shows each
	// teammate's share of it. Statuses are the Schedule's own; see `$lib/home/schedule`.
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
	const share = (value: number) => (counts && counts.total > 0 ? (value / counts.total) * 100 : 0);

	const headline = $derived(
		counts === undefined
			? 'Today'
			: counts.total === 0
				? 'Nothing on the schedule today'
				: `${counts.total} on the schedule`
	);
	const meta = $derived.by(() => {
		if (!schedule || schedule.counts.total === 0) return null;
		const parts: string[] = [];
		if (schedule.peopleOut > 0)
			parts.push(`${schedule.peopleOut} ${schedule.peopleOut === 1 ? 'person' : 'people'} out`);
		if (schedule.lastEndMinutes !== null)
			parts.push(`last one ends ${clockSentence(schedule.lastEndMinutes)}`);
		return parts.length > 0 ? parts.join(' · ') : null;
	});

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

	const statusLabel = { completed: 'Completed', todo: 'Still to do', late: 'Late' } as const;
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
{#snippet row(item: HomeScheduleRow)}
	<li>
		<a
			class={['home-row', `home-row--${item.status}`]}
			href={rowHref(item)}
			aria-label={`${item.timeTop} ${item.timeBottom}, ${item.title}, ${statusLabel[item.status]}`}
		>
			<span
				class={[
					'home-row__time',
					item.status === 'late' && 'home-row__time--late',
					item.status === 'todo' && item.assigneeIds.length === 0 && 'home-row__time--open'
				]}
			>
				<span class="home-row__time-top">{item.timeTop}</span>
				<span class="home-row__time-bottom">{item.timeBottom}</span>
			</span>
			<span class="home-row__main">
				<span class="home-row__title">{item.title}</span>
				<span class="home-row__place">
					<span class="home-row__place-icon" aria-hidden="true">{@html mapPinIcon}</span>
					{[item.place, item.length].filter(Boolean).join(' · ') || 'No address to show'}
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
			<span class={['home-row__status', `home-row__status--${item.status}`]}>
				{#if item.status === 'completed'}
					<span class="home-row__status-icon" aria-hidden="true">{@html checkIcon}</span>
				{:else}
					<span class="home-row__status-dot" aria-hidden="true"></span>
				{/if}
				{statusLabel[item.status]}
			</span>
			<span class="home-row__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
		</a>
	</li>
{/snippet}

<section class="home-schedule" aria-labelledby="{uid}-title" aria-busy={loading}>
	<div class="home-schedule__hero">
		<span class="home-schedule__ring home-schedule__ring--one" aria-hidden="true"></span>
		<span class="home-schedule__ring home-schedule__ring--two" aria-hidden="true"></span>
		<div class="home-schedule__hero-top">
			<div class="home-schedule__headline">
				<p class="home-schedule__eyebrow">
					<span class="home-schedule__eyebrow-icon" aria-hidden="true"
						>{@html calendarEventIcon}</span
					>
					Today
				</p>
				<h2 id="{uid}-title">{loading ? 'Today’s schedule' : headline}</h2>
				{#if meta}<p class="home-schedule__meta">{meta}</p>{/if}
			</div>
			<Button variant="secondary" href={resolve('/(app)/schedule')} class="home-schedule__open">
				<span class="home-schedule__open-icon" aria-hidden="true">{@html calendarIcon}</span>
				Open schedule
			</Button>
		</div>
		{#if counts && counts.total > 0}
			<div
				class="home-schedule__bar"
				role="img"
				aria-label={`${counts.completed} completed, ${counts.todo} still to do`}
			>
				{#if counts.completed > 0}
					<span class="home-schedule__bar-done" style:flex-grow={share(counts.completed)}></span>
				{/if}
				{#if counts.todo > 0}
					<span class="home-schedule__bar-todo" style:flex-grow={share(counts.todo)}></span>
				{/if}
			</div>
		{/if}
		{#if counts}
			<div class="home-schedule__legend">
				<ul class="home-schedule__statuses">
					<li>
						<span class="home-schedule__swatch home-schedule__swatch--done" aria-hidden="true"
						></span>
						Completed <strong>{counts.completed}</strong>
					</li>
					<li>
						<span class="home-schedule__swatch home-schedule__swatch--todo" aria-hidden="true"
						></span>
						Still to do <strong>{counts.todo}</strong>
					</li>
				</ul>
				{#if counts.late > 0 || counts.unassigned > 0}
					<ul class="home-schedule__flags">
						{#if counts.late > 0}
							<li class="home-schedule__flag">
								<span
									class="home-schedule__flag-dot home-schedule__flag-dot--late"
									aria-hidden="true"
								></span>{counts.late} late
							</li>
						{/if}
						{#if counts.unassigned > 0}
							<li class="home-schedule__flag">
								<span
									class="home-schedule__flag-dot home-schedule__flag-dot--open"
									aria-hidden="true"
								></span>{counts.unassigned} unassigned
							</li>
						{/if}
					</ul>
				{/if}
			</div>
		{/if}
	</div>

	<div class="home-schedule__toolbar">
		<p>Visits, assessments and tasks · late ones first, anytime ones last</p>
		<SegmentedControl
			ariaLabel="Group today's schedule"
			size="small"
			bind:value={view}
			options={[
				{ value: 'visit', label: 'By visit' },
				{ value: 'person', label: 'By person' }
			]}
		/>
	</div>

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
	{:else if view === 'visit'}
		{#if schedule.late.length > 0}
			<p class="home-schedule__band home-schedule__band--late">
				<span class="home-schedule__band-icon" aria-hidden="true">{@html alertTriangleIcon}</span>
				LATE FROM EARLIER DAYS
			</p>
			<ul class="home-schedule__rows">
				{#each schedule.late as item (item.key)}{@render row(item)}{/each}
			</ul>
		{/if}
		<p class="home-schedule__band">
			<span class="home-schedule__band-icon" aria-hidden="true">{@html calendarIcon}</span>
			TODAY
		</p>
		{#if schedule.today.length === 0}
			<p class="home-schedule__quiet">Nothing else is booked for today.</p>
		{:else}
			<ul class="home-schedule__rows">
				{#each schedule.today as item (item.key)}{@render row(item)}{/each}
			</ul>
		{/if}
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
</section>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.home-schedule {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__hero {
			position: relative;
			display: grid;
			gap: 18px;
			overflow: hidden;
			padding: 24px 28px 22px;
			color: var(--color-text--reverse);
			background: var(--color-surface--reverse);
		}
		&__ring {
			position: absolute;
			border: 1px solid color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
			border-radius: var(--radius-circle);
			pointer-events: none;

			&--one {
				top: -100px;
				right: 40px;
				width: 260px;
				height: 260px;
			}
			&--two {
				top: -150px;
				right: -10px;
				width: 360px;
				height: 360px;
			}
		}
		&__hero-top {
			position: relative;
			display: flex;
			flex-wrap: wrap;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
		}
		&__headline {
			display: grid;
			gap: 8px;

			h2 {
				color: var(--color-text--reverse);
				font-size: 30px;
				font-weight: 800;
				letter-spacing: -0.9px;
				line-height: 1.1;
			}
		}
		&__eyebrow {
			display: flex;
			align-items: center;
			gap: 8px;
			color: var(--color-icon--secondary);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 1px;
			text-transform: uppercase;
		}
		&__eyebrow-icon {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__meta {
			color: var(--color-text--reverse);
			font-size: 14px;
			font-weight: 500;
			opacity: 0.88;
		}
		&__open-icon {
			display: inline-flex;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__bar {
			position: relative;
			display: flex;
			gap: 4px;
			height: 8px;
		}
		&__bar-done,
		&__bar-todo {
			flex-basis: 0;
			min-width: 8px;
			border-radius: 4px;
		}
		&__bar-done {
			background: var(--color-text--reverse);
		}
		&__bar-todo {
			border: 1px solid color-mix(in srgb, var(--color-text--reverse) 10%, transparent);
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
		}

		&__legend {
			position: relative;
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
		}
		&__statuses,
		&__flags {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 8px 18px;
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__statuses li {
			display: flex;
			align-items: center;
			gap: 7px;
			font-size: 12px;
			font-weight: 600;

			strong {
				font-size: 13px;
				font-weight: 700;
			}
		}
		&__swatch {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);

			&--done {
				background: var(--color-text--reverse);
			}
			&--todo {
				border: 1.5px solid color-mix(in srgb, var(--color-text--reverse) 70%, transparent);
			}
		}
		&__flags {
			gap: 8px;
		}
		&__flag {
			display: flex;
			align-items: center;
			gap: 7px;
			height: 28px;
			padding: 0 11px;
			border: 1px solid color-mix(in srgb, var(--color-text--reverse) 10%, transparent);
			border-radius: 999px;
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
			font-size: 12px;
			font-weight: 600;
		}
		&__flag-dot {
			width: 7px;
			height: 7px;
			border-radius: var(--radius-circle);

			&--late {
				background: var(--color-critical);
			}
			&--open {
				background: var(--color-warning);
			}
		}

		&__toolbar {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
			padding: 12px var(--space-large);

			p {
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}

		&__band {
			display: flex;
			align-items: center;
			gap: 8px;
			padding: 9px var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 0.8px;

			&--late {
				color: var(--color-critical);
			}
		}
		&__band-icon {
			display: inline-flex;

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}
		&__rows {
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__quiet {
			padding: var(--space-base) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			font-size: 13px;
		}
	}

	.home-row {
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 10px var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: inherit;
		text-decoration: none;
		transition: background var(--timing-quick, 0.15s) ease;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: 2px solid var(--color-focus);
			outline-offset: -2px;
		}

		&__time {
			display: flex;
			flex: 0 0 48px;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: 1px;
			height: 48px;
			border: 1px solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);

			&--late {
				border-color: var(--color-critical--surface);
				color: var(--color-critical);
				background: var(--color-critical--surface);
			}
			&--open {
				border-color: var(--color-warning--surface);
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}
		}
		&__time-top {
			font-size: 14px;
			font-weight: 700;
			letter-spacing: -0.3px;
			font-variant-numeric: tabular-nums;
		}
		&__time-bottom {
			color: var(--color-text--secondary);
			font-size: 10px;
			font-weight: 700;
			letter-spacing: 0.4px;
		}
		&__time--late .home-row__time-bottom {
			color: inherit;
		}

		&__main {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 4px;
		}
		&__title {
			overflow: hidden;
			color: var(--color-heading);
			font-size: 14px;
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&--completed &__title {
			color: var(--color-text--secondary);
		}
		&__place {
			display: flex;
			align-items: center;
			gap: 6px;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: 12px;
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__place-icon {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__people {
			display: flex;
			flex: 0 0 76px;
			align-items: center;
		}
		&__avatar {
			display: inline-flex;
			border-radius: var(--radius-circle);
			box-shadow: 0 0 0 2px var(--color-surface);

			& + & {
				margin-left: -6px;
			}
			:global(.avatar--small) {
				width: 30px;
				height: 30px;
				font-size: 10px;
				font-weight: 700;
			}
		}
		&__more {
			margin-left: 4px;
			color: var(--color-text--secondary);
			font-size: 12px;
			font-weight: 700;
		}
		&__assign {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			height: 28px;
			padding: 0 10px;
			border-radius: 999px;
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: 11px;
			font-weight: 700;
		}
		&__assign-icon {
			display: inline-flex;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__status {
			display: inline-flex;
			flex: 0 0 116px;
			align-items: center;
			gap: 5px;
			font-size: 11px;
			font-weight: 700;

			&--completed {
				color: var(--color-text--secondary);
			}
			&--todo {
				color: var(--color-text--secondary);
			}
			&--late {
				color: var(--color-critical);
			}
		}
		&__status--late,
		&__status--todo {
			width: fit-content;
			flex: 0 0 auto;
			padding: 3px 8px;
			border-radius: var(--radius-base);
		}
		&__status--late {
			background: var(--color-critical--surface);
		}
		&__status--todo {
			background: var(--color-surface--background--subtle);
		}
		&__status-dot {
			width: 6px;
			height: 6px;
			border-radius: var(--radius-circle);
			background: currentColor;
		}
		&__status--todo &__status-dot {
			background: var(--color-icon--secondary);
		}
		&__status-icon {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__chevron {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}

	.home-people {
		margin: 0;
		padding: 0;
		list-style: none;

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding: 12px var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
		}
		&__text {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 8px;

			strong {
				color: var(--color-heading);
				font-size: 14px;
				font-weight: 600;
			}
		}
		&__track {
			height: 6px;
			overflow: hidden;
			border-radius: 3px;
			background: var(--color-surface--background--subtle);

			span {
				display: block;
				height: 100%;
				border-radius: 3px;
				background: var(--color-success);
			}
		}
		&__count {
			flex: 0 0 auto;
			color: var(--color-heading);
			font-size: 13px;
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
	}
</style>
