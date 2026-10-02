// The five things that can have happened on a call a person chose to log from a card's Brief.
//
// Order is the order of the buttons. None is ever chosen for the person -- opening the dialler records
// nothing -- and only the first two restart the card's inactivity clock, because only they reached the
// customer (Jafar, 2026-10-02). The database holds the same list and the same rule.
export const CALL_OUTCOMES = [
	'connected',
	'left_voicemail',
	'no_answer',
	'busy',
	'wrong_number'
] as const;

export type CallOutcome = (typeof CALL_OUTCOMES)[number];

export const CALL_OUTCOME_LABELS: Record<CallOutcome, string> = {
	connected: 'Connected',
	left_voicemail: 'Left voicemail',
	no_answer: 'No answer',
	busy: 'Busy',
	wrong_number: 'Wrong number'
};

export function restartsProgress(outcome: CallOutcome) {
	return outcome === 'connected' || outcome === 'left_voicemail';
}

// A call that did not get through is the moment a person wants to try again, so these two offer a
// one-tap follow-up Task. A wrong number does not: trying the same number again helps nobody.
export function offersTryAgain(outcome: CallOutcome) {
	return outcome === 'no_answer' || outcome === 'busy';
}

export type CallLog = {
	id: string;
	opportunity_id: string;
	outcome: CallOutcome;
	note: string | null;
	logged_by: string | null;
	created_at: string;
};
