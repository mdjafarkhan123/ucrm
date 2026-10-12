<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import { fetchMyTimer, myTimerKey, serverOffsetMs } from '$lib/time-clock/api';
	import { createTimerActions } from '$lib/time-clock/timer-actions.svelte';

	// Home's day clock (plan § Timers): Clock in starts general time, Clock out ends the working day, and a
	// visit or Assessment timer pauses the day clock while it runs. It reads the same shared timer query as the header and
	// every visit's Start, so they always agree. Absent for someone who may not time their work.
	const timerQuery = createQuery(() => ({
		queryKey: myTimerKey,
		queryFn: fetchMyTimer,
		staleTime: 30_000
	}));
	const mine = $derived(timerQuery.data);
	const timer = $derived(mine?.timer ?? null);
	const offsetMs = $derived(serverOffsetMs(mine, timerQuery.dataUpdatedAt));
	const actions = createTimerActions();

	const title = $derived(
		timer === null
			? 'You’re clocked out'
			: timer.kind === 'general'
				? 'Clocked in'
				: timer.kind === 'assessment'
					? mine?.clocked_in
						? 'On an assessment'
						: 'Assessment timer running'
					: mine?.clocked_in
						? 'On a visit'
						: 'Visit timer running'
	);
</script>

{#if timerQuery.isPending}
	<div class="day-clock day-clock--pending">
		<LoadingSkeleton variant="heading" label="Loading your day clock" />
	</div>
{:else if timerQuery.isError}
	<section class="day-clock" aria-labelledby="day-clock-heading">
		<div class="day-clock__body">
			<span class="day-clock__eyebrow">Day clock</span>
			<h2 id="day-clock-heading">Your day clock could not be loaded</h2>
			<p>Check your connection, then refresh the page.</p>
		</div>
	</section>
{:else if mine && (mine.can_time || timer)}
	<section class="day-clock" aria-labelledby="day-clock-heading">
		<div class="day-clock__body">
			<span class="day-clock__eyebrow">Day clock</span>
			<div class="day-clock__title">
				<h2 id="day-clock-heading">{title}</h2>
				{#if timer}<RunningClock startedAt={timer.started_at} {offsetMs} flagLong />{/if}
			</div>
			{#if timer === null}
				<p>
					Clock in when your working day starts. Starting a visit’s timer counts that time on the
					job instead.
				</p>
			{:else if timer.kind === 'general'}
				<p>
					General time: travel, the shop, anything not on a visit. Starting a visit’s timer pauses
					it.
				</p>
			{:else}
				<p>
					Timing
					{#if timer.kind === 'visit'}
						<a href={resolve('/(app)/jobs/[id=uuid]', { id: timer.job_id })}
							>{timer.job_number ? `Job #${timer.job_number}` : 'a job'}</a
						>{timer.job_title ? ` · ${timer.job_title}` : ''}.
					{:else if timer.request_id}
						the assessment for
						<a href={resolve('/(app)/requests/[id=uuid]', { id: timer.request_id })}
							>{timer.request_title ?? 'a request'}</a
						>.
					{:else}
						an assessment.
					{/if}
					{mine.clocked_in
						? 'Your day clock is paused and starts again when you stop this timer.'
						: 'You’re not clocked in for the day.'}
				</p>
			{/if}
		</div>
		<div class="day-clock__actions">
			{#if timer === null}
				<Button onclick={actions.clockIn} loading={actions.busy === 'clock-in'}>Clock in</Button>
			{:else if timer.kind === 'general'}
				<Button
					variant="secondary"
					onclick={() => actions.clockOut(timer)}
					loading={actions.busy === 'clock-out'}
					disabled={actions.busy !== null}>Clock out</Button
				>
			{:else}
				<Button
					variant="secondary"
					onclick={() => actions.stop(timer)}
					loading={actions.busy === 'stop'}
					disabled={actions.busy !== null}
					>{timer.kind === 'assessment' ? 'Stop assessment timer' : 'Stop visit timer'}</Button
				>
				{#if mine.clocked_in}
					<Button
						variant="tertiary"
						onclick={() => actions.clockOut(timer)}
						loading={actions.busy === 'clock-out'}
						disabled={actions.busy !== null}>Clock out</Button
					>
				{:else if mine.can_time}
					<Button
						variant="tertiary"
						onclick={actions.clockIn}
						loading={actions.busy === 'clock-in'}
						disabled={actions.busy !== null}>Clock in</Button
					>
				{/if}
			{/if}
		</div>
	</section>
{/if}

<style lang="scss">
	.day-clock {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base) var(--space-large);
		margin-bottom: var(--space-large);
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&--pending {
			min-height: 112px;
		}

		&__body {
			display: grid;
			gap: var(--space-smaller);
			min-width: 0;

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}

			p {
				margin: 0;
				max-width: 62ch;
				color: var(--color-text--secondary);
			}

			a {
				color: var(--color-interactive--subtle);
				font-weight: 700;

				&:hover {
					color: var(--color-interactive--subtle--hover);
				}

				&:focus-visible {
					outline: 2px solid var(--color-interactive--subtle);
					outline-offset: 2px;
					border-radius: var(--radius-small);
				}
			}
		}

		&__eyebrow {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		&__title {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-base);
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
	}

	@media (max-width: 639px) {
		.day-clock {
			align-items: stretch;
			flex-direction: column;
			padding: var(--space-base);

			&__actions > :global(*) {
				flex: 1 1 auto;
			}
		}
	}
</style>
