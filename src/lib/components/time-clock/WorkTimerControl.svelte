<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import TimerElapsed from '$lib/components/time-clock/TimerElapsed.svelte';
	import timerIcon from '@tabler/icons/outline/stopwatch.svg?raw';
	import stopIcon from '@tabler/icons/outline/player-stop.svg?raw';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import TimerRunningElsewhere from '$lib/components/time-clock/TimerRunningElsewhere.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchMyTimer,
		LONG_TIMER_MS,
		myTimerKey,
		refreshAfterTimer,
		runningWorkTimer,
		serverOffsetMs,
		startAssessmentTimer,
		startVisitTimer,
		stopMyTimer,
		type TimerWriteError
	} from '$lib/time-clock/api';
	import { stopMessage } from '$lib/time-clock/messages';
	import playIcon from '@tabler/icons/outline/player-play.svg?raw';

	// Start and Stop for the signed-in person's own timer on one visit or one Assessment (plan § Timers,
	// § Assessment timers). Every copy of this control reads the same shared timer query, so the Schedule
	// popover, the Job page and the Request page agree about what is running. Absent for someone who may not
	// time their work, and on a completed visit or Assessment. A running day clock does not block Start:
	// starting this timer pauses it.
	type Target =
		| { kind: 'visit'; jobId: string; visitId: string }
		| { kind: 'assessment'; assessmentId: string };

	let {
		target,
		completed = false,
		presentation = 'panel'
	}: {
		target: Target;
		/** The full timer panel, or the compact control in a visit row. */
		presentation?: 'panel' | 'inline';
		/** A completed visit or Assessment, or a visit on a closed Job, cannot be timed. Completing it stopped
		 *  its timers. An Assessment not booked for today counts as completed here: only today's are timed. */
		completed?: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const timerQuery = createQuery(() => ({
		queryKey: myTimerKey,
		queryFn: fetchMyTimer,
		staleTime: 30_000
	}));
	const mine = $derived(timerQuery.data);
	const running = $derived(runningWorkTimer(mine));
	const onThis = $derived.by(() => {
		if (!running) return false;
		if (target.kind === 'visit')
			return running.kind === 'visit' && running.visit_id === target.visitId;
		return running.kind === 'assessment' && running.assessment_id === target.assessmentId;
	});
	const offsetMs = $derived(serverOffsetMs(mine, timerQuery.dataUpdatedAt));
	const jobId = $derived(target.kind === 'visit' ? target.jobId : null);

	let busy = $state(false);
	let now = $state(Date.now());
	$effect(() => {
		if (!running) return;
		const tick = setInterval(() => (now = Date.now()), 30_000);
		return () => clearInterval(tick);
	});
	const long = $derived(
		Boolean(onThis && running && now + offsetMs - Date.parse(running.started_at) > LONG_TIMER_MS)
	);
	const since = $derived(
		running
			? new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(
					new Date(running.started_at)
				)
			: ''
	);

	async function start() {
		if (busy) return;
		busy = true;
		try {
			const result =
				target.kind === 'visit'
					? await startVisitTimer(target.jobId, target.visitId)
					: await startAssessmentTimer(target.assessmentId);
			toast.success(
				'Timer started',
				result.day_clock_paused ? 'Your day clock is paused until you stop it.' : undefined
			);
		} catch (caught) {
			toast.error((caught as TimerWriteError).message ?? 'The timer did not start.');
		} finally {
			try {
				await refreshAfterTimer(queryClient, jobId);
			} finally {
				busy = false;
			}
		}
	}

	async function stop() {
		if (busy) return;
		busy = true;
		try {
			const message = stopMessage(await stopMyTimer());
			if (message.tone === 'success') toast.success(message.title, message.detail);
			else toast.info(message.title, message.detail);
		} catch (caught) {
			toast.error((caught as TimerWriteError).message ?? 'The timer did not stop.');
		} finally {
			try {
				await refreshAfterTimer(queryClient, running?.job_id ?? jobId);
			} finally {
				busy = false;
			}
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if (onThis && running) || (mine?.can_time && !completed)}
	<div
		class={[
			'work-timer',
			presentation === 'panel' ? 'work-timer--panel' : 'work-timer--inline',
			onThis && 'work-timer--running',
			long && 'work-timer--long'
		]}
		role="group"
		aria-label={target.kind === 'visit'
			? 'Your timer on this visit'
			: 'Your timer on this assessment'}
	>
		{#if presentation === 'panel'}<span class="work-timer__tile" aria-hidden="true"
				>{@html timerIcon}</span
			>
			<div class="work-timer__copy">
				{#if onThis && running}<strong class="work-timer__elapsed"
						><TimerElapsed startedAt={running.started_at} {offsetMs} /></strong
					><span class:work-timer__warning={long}>{long ? 'Over 12 hours' : `Since ${since}`}</span>
				{:else if running}<TimerRunningElsewhere timer={running} />
				{:else}<strong>Your timer</strong><span
						>Not started on this {target.kind === 'visit' ? 'visit' : 'assessment'}</span
					>{/if}
			</div>{/if}
		{#if onThis && running}
			{#if presentation === 'inline'}<RunningClock
					startedAt={running.started_at}
					{offsetMs}
					joined
					flagLong
				/>{/if}
			<Button size="small" variant="secondary" onclick={stop} loading={busy}
				><span class="work-timer__button-icon" aria-hidden="true">{@html stopIcon}</span>Stop timer</Button
			>
		{:else if running}
			{#if presentation === 'inline'}<TimerRunningElsewhere timer={running} />{/if}
		{:else}
			<Button size="small" variant="secondary" onclick={start} loading={busy}
				><span class="work-timer__button-icon" aria-hidden="true">{@html playIcon}</span>Start timer</Button
			>
		{/if}
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.work-timer {
		--timer-accent: var(--color-time);
		display: inline-flex;
		align-items: center;
		gap: var(--space-slim);
		min-width: 0;
		&--long {
			--timer-accent: var(--color-warning);
		}
		&--panel {
			display: flex;
			width: 100%;
			box-sizing: border-box;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}
		&--panel.work-timer--running {
			border: 1.5px solid var(--timer-accent);
			background: var(--color-surface);
		}
		&__tile {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			flex-shrink: 0;
			border-radius: var(--radius-base);
			background: var(--color-time--surface);
			color: var(--color-time);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&--long &__tile {
			background: var(--color-warning--surface);
			color: var(--color-warning);
		}
		&__copy {
			display: grid;
			gap: 2px;
			flex: 1;
			min-width: 0;
			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
			}
			> span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}
		&__copy &__elapsed {
			--timer-elapsed-size: var(--typography--fontSize-larger);
			--timer-elapsed-color: var(--color-heading);
			letter-spacing: -0.3px;
			font-weight: 700;
		}
		&__copy > .work-timer__warning {
			color: var(--color-warning--onSurface);
			font-weight: 600;
		}
		&__button-icon {
			display: inline-flex;
			color: var(--timer-accent);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		:global(.button__spinner) {
			color: var(--timer-accent);
		}
		&--inline.work-timer--running {
			gap: 0;
			:global(button) {
				border-radius: 0 var(--radius-base) var(--radius-base) 0;
				border-left: 0;
				height: 32px;
			}
		}
	}
	@media (max-width: 479px) {
		.work-timer--panel {
			flex-wrap: wrap;
		}
		.work-timer__copy {
			min-width: 100px;
		}
		.work-timer--inline {
			max-width: 100%;
		}
	}
</style>
