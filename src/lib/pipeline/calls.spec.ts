import { describe, expect, it } from 'vitest';
import {
	CALL_OUTCOMES,
	CALL_OUTCOME_LABELS,
	offersTryAgain,
	restartsProgress,
	type CallOutcome
} from './calls';

describe('call outcomes', () => {
	it('has a plain label for every outcome', () => {
		for (const outcome of CALL_OUTCOMES) {
			expect(CALL_OUTCOME_LABELS[outcome]).toMatch(/\w/);
		}
	});

	it('restarts the inactivity clock only when the call reached the customer', () => {
		const restarting = CALL_OUTCOMES.filter(restartsProgress);
		expect(restarting).toEqual(['connected', 'left_voicemail']);
	});

	it('offers a try-again Task after a call that did not get through, but not a wrong number', () => {
		const offered = CALL_OUTCOMES.filter((outcome: CallOutcome) => offersTryAgain(outcome));
		expect(offered).toEqual(['no_answer', 'busy']);
	});
});
