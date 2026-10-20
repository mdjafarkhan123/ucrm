<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import logoutIcon from '@tabler/icons/outline/logout.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import { fetchMyTimer, myTimerKey, serverOffsetMs } from '$lib/time-clock/api';
	import { createTimerActions } from '$lib/time-clock/timer-actions.svelte';

	// Home's day clock (plan § Timers): Clock in starts general time, Clock out ends the working day, and a
	// visit or Assessment timer pauses the day clock while it runs. It reads the same shared timer query as the header and
	// every visit's Start, so they always agree. Absent for someone who may not time their work.
	// `feature` is the panel on Home's green Today card: white text, a clock tile, white buttons.
	let { tone = 'plain' }: { tone?: 'plain' | 'feature' } = $props();
	const feature = $derived(tone === 'feature');
	const timerQuery = createQuery(() => ({
		queryKey: myTimerKey,
		queryFn: fetchMyTimer,
		staleTime: 30_000
	}));
	const mine = $derived(timerQuery.data);
	const timer = $derived(mine?.timer ?? null);
	const offsetMs = $derived(serverOffsetMs(mine, timerQuery.dataUpdatedAt));
	const actions = createTimerActions();

	const startedFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
	const title = $derived(
		timer === null
			? 'You’re clocked out'
			: timer.kind === 'general'
				? `Clocked in at ${startedFormat.format(new Date(timer.started_at))}`
				: timer.kind === 'assessment'
					? mine?.clocked_in
						? 'On an assessment'
						: 'Assessment timer running'
					: mine?.clocked_in
						? 'On a visit'
						: 'Visit timer running'
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if timerQuery.isPending}
	<div class={['day-clock', 'day-clock--pending', feature && 'day-clock--feature']}>
		<LoadingSkeleton variant="heading" label="Loading your day clock" />
	</div>
{:else if timerQuery.isError}
	<section
		class={['day-clock', feature && 'day-clock--feature']}
		aria-labelledby="day-clock-heading"
	>
		{#if feature}
			<IconTile icon={clockIcon} tone="feature" size={32} />
		{:else}
			<span class="day-clock__mark day-clock__mark--off" aria-hidden="true"
				><span class="day-clock__dot"></span></span
			>
		{/if}
		<div class="day-clock__body">
			<h2 id="day-clock-heading">Your day clock could not be loaded</h2>
			<p>Check your connection, then refresh the page.</p>
		</div>
	</section>
{:else if mine && (mine.can_time || timer)}
	<section
		class={['day-clock', feature && 'day-clock--feature']}
		aria-labelledby="day-clock-heading"
	>
		{#if feature}
			<IconTile icon={clockIcon} tone="feature" size={32} />
		{:else}
			<span class={['day-clock__mark', timer === null && 'day-clock__mark--off']} aria-hidden="true"
				><span class="day-clock__dot"></span></span
			>
		{/if}
		<div class="day-clock__body">
			{#if feature && timer?.kind === 'general'}
				<h2 id="day-clock-heading" class="day-clock__on">
					<span class="day-clock__live" aria-hidden="true"></span>On the clock ·
					<RunningClock startedAt={timer.started_at} {offsetMs} flagLong />
				</h2>
			{:else}
				<h2 id="day-clock-heading">{title}</h2>
			{/if}
			{#if timer === null}
				<p>Clock in when your working day starts.</p>
			{:else if feature && timer.kind === 'general'}
				<p>Since {startedFormat.format(new Date(timer.started_at))}</p>
			{:else if timer.kind === 'general'}
				<p class="day-clock__running">
					<RunningClock startedAt={timer.started_at} {offsetMs} flagLong />
				</p>
			{:else}
				<p>
					{#if timer.kind === 'visit'}
						<a href={resolve('/(app)/jobs/[id=uuid]', { id: timer.job_id })}
							>{timer.job_number ? `Job #${timer.job_number}` : 'a job'}</a
						>{timer.job_title ? ` · ${timer.job_title}` : ''}
					{:else if timer.request_id}
						<a href={resolve('/(app)/requests/[id=uuid]', { id: timer.request_id })}
							>{timer.request_title ?? 'a request'}</a
						>
					{:else}
						an assessment
					{/if}
					· <RunningClock startedAt={timer.started_at} {offsetMs} flagLong />
				</p>
				<p class="day-clock__note">
					{mine.clocked_in
						? 'Your day clock is paused until you stop this timer.'
						: 'You’re not clocked in for the day.'}
				</p>
			{/if}
		</div>
		<div class="day-clock__actions">
			{#if timer === null}
				<Button
					variant={feature ? 'secondary' : 'primary'}
					onclick={actions.clockIn}
					loading={actions.busy === 'clock-in'}>Clock in</Button
				>
			{:else if timer.kind === 'general'}
				<Button
					variant="secondary"
					onclick={() => actions.clockOut(timer)}
					loading={actions.busy === 'clock-out'}
					disabled={actions.busy !== null}
				>
					<span class="day-clock__button-icon" aria-hidden="true">{@html logoutIcon}</span>
					Clock out
				</Button>
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

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.day-clock {
		display: flex;
		align-items: center;
		gap: 14px;
		width: fit-content;
		max-width: 100%;
		padding: 8px 8px 8px 16px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&--pending {
			width: 280px;
			min-height: 64px;
		}

		&__mark {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 28px;
			height: 28px;
			border-radius: var(--radius-base);
			background: var(--color-success--surface);

			&--off {
				background: var(--color-surface--background--subtle);

				.day-clock__dot {
					background: var(--color-icon--secondary);
				}
			}
		}
		&__dot {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-success);
		}

		&__body {
			display: grid;
			gap: 2px;
			min-width: 0;

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: 13px;
				font-weight: 600;
			}
			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: 12px;
				font-weight: 500;
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
		&__running :global(.running-clock) {
			padding: 0;
			background: none;
			font-size: 12px;
			font-weight: 500;
			font-variant-numeric: tabular-nums;
		}
		&__note {
			max-width: 34ch;
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
		&__button-icon {
			display: inline-flex;

			:global(svg) {
				width: 15px;
				height: 15px;
			}
		}
	}

	/* On Home's green Today card: a translucent panel with white text and a white clock tile. */
	.day-clock--feature {
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-base);
		border-color: var(--color-feature--border);
		border-radius: var(--radius-large);
		background: var(--color-feature--subtle);

		&.day-clock--pending {
			min-height: 58px;
		}
		.day-clock__body {
			h2 {
				color: var(--color-feature--text);
				font-size: var(--typography--fontSize-base);
			}
			p {
				color: var(--color-feature--text--secondary);
				font-weight: 400;
			}
			a {
				color: var(--color-feature--text);
				text-decoration: underline;

				&:hover {
					color: var(--color-feature--text);
				}
				&:focus-visible {
					outline-color: var(--color-feature--text);
				}
			}
			:global(.running-clock) {
				padding: 0;
				color: inherit;
				background: none;
				font-size: inherit;
				font-weight: inherit;
				font-variant-numeric: tabular-nums;
			}
			:global(.running-clock__pulse) {
				display: none;
			}
			:global(.running-clock *) {
				color: inherit;
			}
		}
		.day-clock__on {
			display: inline-flex;
			align-items: center;
			gap: 6px;
		}
		.day-clock__live {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-feature--text);
		}
	}

	@media (max-width: 639px) {
		.day-clock {
			width: 100%;
			flex-wrap: wrap;

			&__actions {
				width: 100%;
			}
			&__actions > :global(*) {
				flex: 1 1 auto;
			}
		}
	}
</style>
