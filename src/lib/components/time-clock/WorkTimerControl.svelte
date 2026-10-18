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
		concept = false
	}: {
		target: Target;
		/** The concept look (Job details `tNdkX`): a small white "Start timer" with a play icon, so the row's
		 *  green stays with the page's one main action. */
		concept?: boolean;
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

<!-- eslint-disable svelte/no-at-html-tags -->
{#if onThis && running}
	<div
		class="work-timer work-timer--running"
		role="group"
		aria-label={target.kind === 'visit'
			? 'Your timer on this visit'
			: 'Your timer on this assessment'}
	>
		<RunningClock startedAt={running.started_at} {offsetMs} />
		<Button size="small" variant="secondary" onclick={stop} loading={busy}>Stop timer</Button>
	</div>
{:else if mine?.can_time && !completed}
	{#if running}
		<TimerRunningElsewhere timer={running} />
	{:else if concept}
		<Button size="small" variant="secondary" onclick={start} loading={busy}>
			{@html playIcon}Start timer
		</Button>
	{:else}
		<Button size="small" onclick={start} loading={busy}>Start timer</Button>
	{/if}
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.work-timer {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
</style>
