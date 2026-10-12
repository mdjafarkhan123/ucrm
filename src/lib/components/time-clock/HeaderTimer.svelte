<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import { fetchMyTimer, myTimerKey, runningTimerLabel, serverOffsetMs } from '$lib/time-clock/api';
	import { createTimerActions } from '$lib/time-clock/timer-actions.svelte';
	import stopIcon from '@tabler/icons/outline/player-stop.svg?raw';

	// The signed-in person's running timer on every page (plan § Timers): what runs, for how long, the
	// 12-hour flag, and a Stop. It is the only Stop left for a timer whose visit or Assessment was deleted. The day clock's
	// Stop is Clock out. Nothing shows while nothing runs; Home offers Clock in.
	const timerQuery = createQuery(() => ({
		queryKey: myTimerKey,
		queryFn: fetchMyTimer,
		staleTime: 30_000
	}));
	const mine = $derived(timerQuery.data);
	const timer = $derived(mine?.timer ?? null);
	const offsetMs = $derived(serverOffsetMs(mine, timerQuery.dataUpdatedAt));
	const actions = createTimerActions();

	const label = $derived(timer ? runningTimerLabel(timer) : '');
</script>

{#snippet running(startedAt: string)}
	<RunningClock {startedAt} {offsetMs} flagLong />
	<span class="header-timer__label">{label}</span>
{/snippet}

<!-- eslint-disable svelte/no-at-html-tags -->
{#if timer}
	<div class="header-timer" role="group" aria-label="Your running timer">
		{#if timer.kind === 'visit'}
			<a
				class="header-timer__link"
				href={resolve('/(app)/jobs/[id=uuid]', { id: timer.job_id })}
				title={timer.job_title ? `${label} · ${timer.job_title}` : label}
			>
				{@render running(timer.started_at)}
			</a>
		{:else if timer.kind === 'assessment' && timer.request_id}
			<a
				class="header-timer__link"
				href={resolve('/(app)/requests/[id=uuid]', { id: timer.request_id })}
				title={timer.request_title ? `${label} · ${timer.request_title}` : label}
			>
				{@render running(timer.started_at)}
			</a>
		{:else}
			<a class="header-timer__link" href={resolve('/(app)/dashboard')} title={label}>
				{@render running(timer.started_at)}
			</a>
		{/if}
		{#if timer.kind === 'general'}
			<button
				class="header-timer__stop"
				type="button"
				onclick={() => actions.clockOut(timer)}
				title="Clock out"
				disabled={actions.busy !== null}
				aria-busy={actions.busy === 'clock-out'}
			>
				<span class="header-timer__icon" aria-hidden="true">{@html stopIcon}</span>
				<span class="header-timer__stop-text"
					>{actions.busy === 'clock-out' ? 'Clocking out…' : 'Clock out'}</span
				>
			</button>
		{:else}
			<button
				class="header-timer__stop"
				type="button"
				onclick={() => actions.stop(timer)}
				title="Stop timer"
				disabled={actions.busy !== null}
				aria-busy={actions.busy === 'stop'}
				aria-label={`Stop timer on ${label}`}
			>
				<span class="header-timer__icon" aria-hidden="true">{@html stopIcon}</span>
				<span class="header-timer__stop-text">{actions.busy === 'stop' ? 'Stopping…' : 'Stop'}</span
				>
			</button>
		{/if}
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Never squeezed into its neighbours: the search box gives way first.
	.header-timer {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		min-width: 0;
		min-height: 40px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.header-timer__link {
		display: inline-flex;
		flex: 1 1 auto;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
		align-self: stretch;
		padding: 0 var(--space-small) 0 var(--space-smaller);
		border-radius: var(--radius-base) 0 0 var(--radius-base);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-decoration: none;
		transition: background var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.header-timer__label {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.header-timer__stop {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		align-self: stretch;
		gap: var(--space-smaller);
		padding: 0 var(--space-small);
		border: 0;
		border-left: var(--border-base) solid var(--color-border);
		border-radius: 0 var(--radius-base) var(--radius-base) 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		white-space: nowrap;
		cursor: pointer;
		transition: background var(--timing-quick);

		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			color: var(--color-disabled);
			cursor: not-allowed;
		}
	}

	.header-timer__icon,
	.header-timer__icon :global(svg) {
		display: inline-flex;
		width: 18px;
		height: 18px;
	}

	.header-timer__icon {
		color: var(--color-critical);

		.header-timer__stop:disabled & {
			color: inherit;
		}
	}

	// On a phone the header's icons fill its first row, so the running timer takes a full row of its own
	// beneath them, where its time, what it is on and its Stop all stay readable and easy to tap.
	@media (max-width: 767px) {
		.header-timer {
			order: 10;
			flex: 1 0 100%;
			min-height: 44px;
		}

		.header-timer__link {
			padding-left: var(--space-small);
		}
	}

	// Between a tablet and a wide laptop the header beside the sidebar is short of room, so the timer keeps
	// its time and Stop icon. The label, the Stop wording and the 12-hour words stay for screen readers; the
	// amber pill still flags a long timer, and Home spells it out.
	@media (min-width: 768px) and (max-width: 1199px) {
		.header-timer__label {
			display: none;
		}

		.header-timer__stop {
			justify-content: center;
			min-width: 40px;
			padding: 0;
		}

		.header-timer__stop-text,
		.header-timer__link :global(.running-clock__flag) {
			position: absolute;
			width: 1px;
			height: 1px;
			margin: -1px;
			padding: 0;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
			border: 0;
		}
	}

	// A narrow phone has no room for both the 12-hour warning and the label, and the warning matters more;
	// the Stop beside it still says Clock out or Stop.
	@media (max-width: 480px) {
		.header-timer__link:has(:global(.running-clock--long)) .header-timer__label {
			display: none;
		}
	}
</style>
