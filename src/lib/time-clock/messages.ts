import { durationLabel, type StopTimerResult } from '$lib/time-clock/api';

// What a person is told after a timer moves. Every Stop and Clock out control uses these, so the same event
// always reads the same wherever it was pressed.

export type TimerMessage = { tone: 'success' | 'info'; title: string; detail?: string };

const resumedNote = ' Your day clock is running again.';

export function stopMessage(result: StopTimerResult): TimerMessage {
	if (!result.stopped) {
		return {
			tone: 'info',
			title: 'This timer was already stopped',
			detail: 'Its hours were recorded once.'
		};
	}
	const resumed = result.day_clock_resumed ? resumedNote : '';
	if (!result.recorded) {
		return {
			tone: 'info',
			title: 'Timer stopped',
			detail: `It ran for less than a minute, so no hours were recorded.${resumed}`
		};
	}
	if (result.kind === 'general') {
		return {
			tone: 'success',
			title: 'Clocked out',
			detail: `${durationLabel(result.minutes)} of general time recorded.`
		};
	}
	if (result.kind === 'assessment') {
		return {
			tone: 'success',
			title: 'Timer stopped',
			detail: `${durationLabel(result.minutes)} recorded for this assessment.${resumed}`
		};
	}
	return {
		tone: 'success',
		title: 'Timer stopped',
		detail: `${durationLabel(result.minutes)} added to this job’s hours.${resumed}`
	};
}

export function clockOutMessage(result: StopTimerResult): TimerMessage {
	if (!result.stopped) {
		return {
			tone: 'info',
			title: 'You were already clocked out',
			detail: 'Your hours were recorded once.'
		};
	}
	if (!result.recorded) {
		return {
			tone: 'info',
			title: 'Clocked out',
			detail: 'That ran for less than a minute, so no hours were recorded.'
		};
	}
	if (result.kind === 'visit') {
		return {
			tone: 'success',
			title: 'Clocked out',
			detail: `Your visit timer stopped too: ${durationLabel(result.minutes)} added to the job’s hours.`
		};
	}
	if (result.kind === 'assessment') {
		return {
			tone: 'success',
			title: 'Clocked out',
			detail: `Your assessment timer stopped too: ${durationLabel(result.minutes)} recorded.`
		};
	}
	return {
		tone: 'success',
		title: 'Clocked out',
		detail: `${durationLabel(result.minutes)} of general time recorded.`
	};
}

export function clockInMessage(result: {
	already_clocked_in: boolean;
	paused_by_visit: boolean;
}): TimerMessage {
	if (result.paused_by_visit) {
		return {
			tone: 'success',
			title: 'Clocked in',
			detail: 'Your day clock starts when you stop your running timer.'
		};
	}
	if (result.already_clocked_in) return { tone: 'info', title: 'You were already clocked in' };
	return { tone: 'success', title: 'Clocked in' };
}
