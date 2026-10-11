import type { QueryClient } from '@tanstack/svelte-query';
import { jobDetailKey, jobLaborKey } from '$lib/jobs/api';

// Time clock (docs/time-clock-behavior-contract.md). The signed-in person's own running timer is one shared
// query: every Start/Stop control and the Job's Labor list read it, so they can never disagree about whether
// a timer is running.

export type TimerWriteError = Error & { reason?: string; status?: number };

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string; reason?: string });
		const error = new Error(result.error ?? fallback) as TimerWriteError;
		error.reason = result.reason;
		error.status = response.status;
		throw error;
	}
	return response.json();
}

export type RunningTimer = {
	kind: 'visit';
	job_id: string;
	job_number: number | null;
	job_title: string | null;
	/** Null when the visit was deleted while the timer ran; the hours then land on the Job alone. */
	visit_id: string | null;
	visit_date: string | null;
	started_at: string;
};

export type MyTimer = {
	timer: RunningTimer | null;
	/** Whether this person may start their own timer at all. Without it no Start control is offered. */
	can_time: boolean;
	/** The server's clock when this was read. Running time is counted from it, never from the phone's. */
	server_now: string;
};

export const myTimerKey = ['time-clock', 'timer'] as const;

export async function fetchMyTimer(): Promise<MyTimer> {
	const response = await fetch('/api/time-clock/timer');
	return readOrThrow<MyTimer>(response, 'Your timer could not be loaded.');
}

export async function startVisitTimer(
	jobId: string,
	visitId: string
): Promise<{ started_at: string; already_running: boolean }> {
	const response = await fetch('/api/time-clock/timer', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ job_id: jobId, visit_id: visitId })
	});
	return readOrThrow(response, 'The timer did not start. Check your connection and try again.');
}

export type StopTimerResult =
	| { stopped: false; already_stopped: true; recorded: false }
	| { stopped: true; recorded: false; too_short: true }
	| { stopped: true; recorded: true; entry_id: string; job_id: string; minutes: number };

export async function stopMyTimer(): Promise<StopTimerResult> {
	const response = await fetch('/api/time-clock/timer/stop', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: '{}'
	});
	return readOrThrow(response, 'The timer did not stop. Check your connection and try again.');
}

// Everything a timer moving can change: the person's own timer, and the Job's Labor list and costing card
// (labour cost counts once the timer stops). Completing a visit stops timers too, so it calls this as well.
export async function refreshAfterTimer(queryClient: QueryClient, jobId: string | null) {
	await Promise.all([
		queryClient.invalidateQueries({ queryKey: myTimerKey }),
		...(jobId
			? [
					queryClient.invalidateQueries({ queryKey: jobLaborKey(jobId) }),
					queryClient.invalidateQueries({ queryKey: jobDetailKey(jobId) })
				]
			: [])
	]);
}

// Recorded hours as a timesheet reads them out loud: "40m", "2h", "1h 30m".
export function durationLabel(minutes: number) {
	const hours = Math.floor(minutes / 60);
	const rest = minutes % 60;
	if (hours === 0) return `${rest}m`;
	if (rest === 0) return `${hours}h`;
	return `${hours}h ${rest}m`;
}

// How long a timer has run, as a running clock reads: 0:42:07, 12:03:55. The server's offset is applied so a
// phone set to the wrong time still shows the true duration.
export function elapsedLabel(startedAt: string, now: number) {
	const seconds = Math.max(0, Math.floor((now - Date.parse(startedAt)) / 1000));
	const hours = Math.floor(seconds / 3600);
	const minutes = Math.floor((seconds % 3600) / 60);
	const rest = seconds % 60;
	return `${hours}:${String(minutes).padStart(2, '0')}:${String(rest).padStart(2, '0')}`;
}
