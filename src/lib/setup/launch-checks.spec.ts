import { describe, expect, it } from 'vitest';
import {
	LAUNCH_CHECKS,
	LAUNCH_CHECK_HINT,
	LAUNCH_CHECK_TITLE,
	launchCheckWaitingLabel,
	launchChecklistFrom,
	launchWaitLine,
	uncheckedLaunchLines,
	type LaunchCheckLine
} from './launch-checks';

const line = (key: LaunchCheckLine['key'], state: LaunchCheckLine['state']): LaunchCheckLine => ({
	key,
	state,
	reason: null,
	checked_at: null,
	waiting_on: []
});

describe('launch checks', () => {
	it('words every line', () => {
		for (const check of LAUNCH_CHECKS) {
			expect(LAUNCH_CHECK_TITLE[check.key]).toBeTruthy();
			expect(LAUNCH_CHECK_HINT[check.key]).toBeTruthy();
		}
	});

	it('lets Ask wait only for unchecked lines, never for one waiting on a provider', () => {
		const checklist = {
			lines: [
				line('web_address', 'waiting'),
				line('imports', 'not_applicable'),
				line('email_delivery', 'checked'),
				line('everything_else', 'unchecked')
			],
			waits: []
		};
		expect(uncheckedLaunchLines(checklist).map((item) => item.key)).toEqual(['everything_else']);
		expect(uncheckedLaunchLines({ ...checklist, lines: checklist.lines.slice(0, 3) })).toEqual([]);
	});

	it('names who a waiting line is on, once each', () => {
		expect(launchCheckWaitingLabel(['texting_approval'])).toBe('Waiting on the phone carriers');
		expect(launchCheckWaitingLabel(['texting_approval', 'number_transfer'])).toBe(
			'Waiting on the phone carriers and the old phone company'
		);
		expect(launchWaitLine({ key: 'google_profile', status: 'in_review' })).toBe(
			'Google profile — Being reviewed by Google'
		);
	});

	it('reads a kept list and ignores anything that is not one', () => {
		expect(launchChecklistFrom(null)).toBeNull();
		expect(launchChecklistFrom({ lines: 'x' })).toBeNull();
		expect(
			launchChecklistFrom({
				lines: [line('phone_look', 'checked'), { key: 'gone', state: 'checked' }],
				waits: [
					{ key: 'website_address', status: 'in_review' },
					{ key: 'gone', status: 'x' }
				]
			})
		).toEqual({
			lines: [line('phone_look', 'checked')],
			waits: [{ key: 'website_address', status: 'in_review' }]
		});
	});
});
