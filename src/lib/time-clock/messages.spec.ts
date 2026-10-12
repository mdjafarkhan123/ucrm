import { describe, expect, it } from 'vitest';
import { clockInMessage, clockOutMessage, stopMessage } from './messages';

describe('what a person is told when a timer moves', () => {
	it('says a stopped visit timer’s hours went to the job, and when the day clock resumed', () => {
		const base = {
			stopped: true,
			recorded: true,
			kind: 'visit',
			entry_id: 'entry-1',
			job_id: 'job-1',
			minutes: 40
		} as const;
		expect(stopMessage({ ...base, day_clock_resumed: false })).toEqual({
			tone: 'success',
			title: 'Timer stopped',
			detail: '40m added to this job’s hours.'
		});
		expect(stopMessage({ ...base, minutes: 125, day_clock_resumed: true }).detail).toBe(
			'2h 5m added to this job’s hours. Your day clock is running again.'
		);
	});

	it('says a stopped assessment timer’s time was recorded for the assessment, not a job', () => {
		const result = {
			stopped: true,
			recorded: true,
			kind: 'assessment',
			entry_id: 'entry-2',
			job_id: null,
			request_id: 'request-1',
			minutes: 40,
			day_clock_resumed: true
		} as const;
		expect(stopMessage(result)).toEqual({
			tone: 'success',
			title: 'Timer stopped',
			detail: '40m recorded for this assessment. Your day clock is running again.'
		});
		expect(clockOutMessage(result).detail).toBe('Your assessment timer stopped too: 40m recorded.');
	});

	it('says a mistaken tap recorded nothing', () => {
		expect(
			stopMessage({
				stopped: true,
				recorded: false,
				too_short: true,
				kind: 'visit',
				day_clock_resumed: false
			})
		).toEqual({
			tone: 'info',
			title: 'Timer stopped',
			detail: 'It ran for less than a minute, so no hours were recorded.'
		});
		expect(
			clockOutMessage({
				stopped: true,
				recorded: false,
				too_short: true,
				kind: 'general',
				day_clock_resumed: false
			}).detail
		).toBe('That ran for less than a minute, so no hours were recorded.');
	});

	it('reads clocking out as general time, or as the visit timer stopping too', () => {
		expect(
			clockOutMessage({
				stopped: true,
				recorded: true,
				kind: 'general',
				entry_id: 'entry-2',
				job_id: null,
				minutes: 240,
				day_clock_resumed: false
			})
		).toEqual({ tone: 'success', title: 'Clocked out', detail: '4h of general time recorded.' });
		expect(
			clockOutMessage({
				stopped: true,
				recorded: true,
				kind: 'visit',
				entry_id: 'entry-3',
				job_id: 'job-1',
				minutes: 45,
				day_clock_resumed: false
			}).detail
		).toBe('Your visit timer stopped too: 45m added to the job’s hours.');
	});

	it('treats a second press as already done, not as an error', () => {
		const already = { stopped: false, already_stopped: true, recorded: false } as const;
		expect(stopMessage(already).title).toBe('This timer was already stopped');
		expect(clockOutMessage(already).title).toBe('You were already clocked out');
		expect(clockInMessage({ already_clocked_in: true, paused_by_visit: false }).title).toBe(
			'You were already clocked in'
		);
	});

	it('explains that clocking in during a visit starts the day clock after it', () => {
		expect(clockInMessage({ already_clocked_in: false, paused_by_visit: true })).toEqual({
			tone: 'success',
			title: 'Clocked in',
			detail: 'Your day clock starts when you stop your running timer.'
		});
	});
});
