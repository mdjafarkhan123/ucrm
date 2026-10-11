import { useQueryClient } from '@tanstack/svelte-query';
import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
import {
	clockIn,
	clockOut,
	refreshAfterTimer,
	stopMyTimer,
	type RunningTimer,
	type TimerWriteError
} from '$lib/time-clock/api';
import {
	clockInMessage,
	clockOutMessage,
	stopMessage,
	type TimerMessage
} from '$lib/time-clock/messages';

export type TimerAction = 'clock-in' | 'clock-out' | 'stop';

// Clock in, Clock out and Stop for the signed-in person's own timer, shared by the header's running timer
// and Home's day clock so both say the same thing and refresh the same queries. Call during component setup.
export function createTimerActions() {
	const queryClient = useQueryClient();
	const toast = getToastManager();
	let busy = $state<TimerAction | null>(null);

	function show(message: TimerMessage) {
		if (message.tone === 'success') toast.success(message.title, message.detail);
		else toast.info(message.title, message.detail);
	}

	async function run(
		action: TimerAction,
		timer: RunningTimer | null,
		task: () => Promise<TimerMessage>
	) {
		if (busy) return;
		busy = action;
		try {
			show(await task());
		} catch (caught) {
			const fallback =
				action === 'clock-in'
					? 'You were not clocked in.'
					: action === 'clock-out'
						? 'You were not clocked out.'
						: 'The timer did not stop.';
			toast.error((caught as TimerWriteError).message ?? fallback);
		} finally {
			busy = null;
			// A stopped visit timer changes that Job's hours; the person's own timer changes every time.
			await refreshAfterTimer(queryClient, timer?.job_id ?? null);
		}
	}

	return {
		get busy() {
			return busy;
		},
		clockIn: () => run('clock-in', null, async () => clockInMessage(await clockIn())),
		clockOut: (timer: RunningTimer | null) =>
			run('clock-out', timer, async () => clockOutMessage(await clockOut())),
		stop: (timer: RunningTimer | null) =>
			run('stop', timer, async () => stopMessage(await stopMyTimer()))
	};
}
