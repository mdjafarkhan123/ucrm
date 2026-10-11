<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import RunningClock from '$lib/components/time-clock/RunningClock.svelte';
	import TimerRunningElsewhere from '$lib/components/time-clock/TimerRunningElsewhere.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchMyTimer,
		myTimerKey,
		refreshAfterTimer,
		runningVisitTimer,
		serverOffsetMs,
		startVisitTimer,
		stopMyTimer,
		type TimerWriteError
	} from '$lib/time-clock/api';
	import { stopMessage } from '$lib/time-clock/messages';

	// Start and Stop for the signed-in person's own timer on one visit (plan § Timers). Every copy of this
	// control reads the same shared timer query, so the Schedule popover and the Job page agree about what is
	// running. Absent for someone who may not time their work, and on a completed visit. A running day clock
	// does not block Start: starting the visit's timer pauses it.
	let {
		jobId,
		visitId,
		completed = false
	}: {
		jobId: string;
		visitId: string;
		/** A completed visit, or one on a closed Job, cannot be timed. Completing it stopped its timers. */
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
	const running = $derived(runningVisitTimer(mine));
	const onThisVisit = $derived(running !== null && running.visit_id === visitId);
	const offsetMs = $derived(serverOffsetMs(mine, timerQuery.dataUpdatedAt));

	let busy = $state(false);

	async function start() {
		if (busy) return;
		busy = true;
		try {
			const result = await startVisitTimer(jobId, visitId);
			toast.success(
				'Timer started',
				result.day_clock_paused ? 'Your day clock is paused until you stop it.' : undefined
			);
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
			const message = stopMessage(await stopMyTimer());
			if (message.tone === 'success') toast.success(message.title, message.detail);
			else toast.info(message.title, message.detail);
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
		<RunningClock startedAt={running.started_at} {offsetMs} />
		<Button size="small" variant="secondary" onclick={stop} loading={busy}>Stop timer</Button>
	</div>
{:else if mine?.can_time && !completed}
	{#if running}
		<TimerRunningElsewhere timer={running} />
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
</style>
