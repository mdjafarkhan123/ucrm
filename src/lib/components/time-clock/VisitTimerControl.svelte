<script lang="ts">
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import TimerElapsed from '$lib/components/time-clock/TimerElapsed.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		durationLabel,
		fetchMyTimer,
		myTimerKey,
		refreshAfterTimer,
		startVisitTimer,
		stopMyTimer,
		type TimerWriteError
	} from '$lib/time-clock/api';

	// Start and Stop for the signed-in person's own timer on one visit (plan § Timers). Every copy of this
	// control reads the same shared timer query, so the Schedule popover and the Job page agree about what is
	// running. Absent for someone who may not time their work, and on a completed visit.
	let {
		jobId,
		visitId,
		completed = false
	}: {
		jobId: string;
		visitId: string;
		/** A completed visit cannot be timed; completing it already stopped any timer on it. */
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
	const running = $derived(mine?.timer ?? null);
	const onThisVisit = $derived(running !== null && running.visit_id === visitId);
	// How far the server's clock is ahead of this device's when the timer was read.
	const offsetMs = $derived(mine ? Date.parse(mine.server_now) - timerQuery.dataUpdatedAt : 0);

	let busy = $state(false);

	async function start() {
		if (busy) return;
		busy = true;
		try {
			await startVisitTimer(jobId, visitId);
			toast.success('Timer started');
		} catch (caught) {
			toast.error((caught as TimerWriteError).message ?? 'The timer did not start.');
		} finally {
			busy = false;
			await refreshAfterTimer(queryClient, jobId);
		}
	}

	async function stop() {
		if (busy) return;
		busy = true;
		try {
			const result = await stopMyTimer();
			if (result.recorded) {
				toast.success(
					'Timer stopped',
					`${durationLabel(result.minutes)} added to this job’s hours.`
				);
			} else if (result.stopped) {
				toast.info('Timer stopped', 'It ran for less than a minute, so no hours were recorded.');
			} else {
				toast.info('This timer was already stopped', 'Its hours were recorded once.');
			}
		} catch (caught) {
			toast.error((caught as TimerWriteError).message ?? 'The timer did not stop.');
		} finally {
			busy = false;
			await refreshAfterTimer(queryClient, running?.job_id ?? jobId);
		}
	}
</script>

{#if onThisVisit && running}
	<div class="visit-timer visit-timer--running" role="group" aria-label="Your timer on this visit">
		<span class="visit-timer__status">
			<span class="visit-timer__pulse" aria-hidden="true"></span>
			<TimerElapsed startedAt={running.started_at} {offsetMs} />
		</span>
		<Button size="small" variant="secondary" onclick={stop} loading={busy}>Stop timer</Button>
	</div>
{:else if mine?.can_time && !completed}
	{#if running}
		<!-- Only one timer runs at a time. Rather than offer a Start that can only be refused, say where the
		     running one is so the person can go and stop it. -->
		<p class="visit-timer__elsewhere">
			Your timer is running on
			<a href={resolve('/(app)/jobs/[id=uuid]', { id: running.job_id })}>
				{running.job_number ? `Job #${running.job_number}` : 'another job'}
			</a>
		</p>
	{:else}
		<Button size="small" onclick={start} loading={busy}>Start timer</Button>
	{/if}
{/if}

<style lang="scss">
	.visit-timer {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	.visit-timer__status {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-small);
		border-radius: var(--radius-base);
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}

	.visit-timer__pulse {
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		background: var(--color-success);
		animation: visit-timer-pulse 1.6s ease-in-out infinite;
	}

	.visit-timer__elsewhere {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);

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

	@keyframes visit-timer-pulse {
		0%,
		100% {
			opacity: 1;
		}

		50% {
			opacity: 0.35;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.visit-timer__pulse {
			animation: none;
		}
	}
</style>
