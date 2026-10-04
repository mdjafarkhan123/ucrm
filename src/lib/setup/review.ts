// Client onboarding C3: Uplift's review of a client's sent setup, one section at a time (plan §4; Content
// Snare's approve / send back with a reason). The database keeps only Uplift's latest decision on each section
// and the send it was made on (`organization_setup_section_reviews`); what that decision means now depends on
// what the client has sent since, and is worked out here so Jafar's page and the client's read it the same way.

import { sameAnswer } from '$lib/setup/check';
import type { SetupAnswers } from '$lib/setup/catalogue';

export const SETUP_REVIEW_NOTE_MAX = 2000;

/** A stored decision, as `organization_setup_section_reviews` holds it. */
export type SetupReviewDecision = {
	section_key: string;
	decision: 'accepted' | 'returned';
	/** The send it was made on. */
	submission_number: number;
	note: string | null;
	question_keys: string[];
	reviewed_by_email: string;
	reviewed_at: string;
};

/**
 * Where a section stands with Uplift, against the newest send:
 * - `to_review` — sent, not decided yet;
 * - `accepted` — accepted, and the newest send has the same answers for it;
 * - `changed` — accepted earlier, but the client has since sent different answers for it;
 * - `returned` — sent back on the newest send: the client's move;
 * - `resent` — sent back earlier, and the client has sent again since.
 */
export type SetupReviewState = 'to_review' | 'accepted' | 'changed' | 'returned' | 'resent';

export type SetupSectionReview = {
	state: SetupReviewState;
	/** Uplift's latest decision, whatever it means now; null before the first. */
	decision: SetupReviewDecision | null;
};

/** Labels and badge colours for each state, as Jafar's Setup tab shows them. */
export const SETUP_REVIEW_STATE: Record<
	SetupReviewState,
	{ label: string; badge: 'success' | 'warning' | 'informative' | 'inactive' }
> = {
	to_review: { label: 'To review', badge: 'informative' },
	accepted: { label: 'Accepted', badge: 'success' },
	changed: { label: 'Changed since accepted', badge: 'informative' },
	returned: { label: 'Sent back', badge: 'warning' },
	resent: { label: 'Sent again', badge: 'informative' }
};

/** The same answers for every one of `factKeys` in both sends. A question missing from both counts as the same. */
export function sameSectionAnswers(
	factKeys: readonly string[],
	a: SetupAnswers,
	b: SetupAnswers
): boolean {
	return factKeys.every((key) => sameAnswer(a[key], b[key]));
}

/**
 * What one section's decision means against the newest send. `answersOf(n)` gives send n's answers, and is
 * only asked for the send an acceptance was made on, when that is an earlier one.
 */
export function setupSectionReview(input: {
	decision: SetupReviewDecision | null;
	newestNumber: number;
	newestAnswers: SetupAnswers;
	factKeys: readonly string[];
	answersOf: (submissionNumber: number) => SetupAnswers | undefined;
}): SetupSectionReview {
	const { decision, newestNumber } = input;
	if (!decision) return { state: 'to_review', decision };
	const current = decision.submission_number === newestNumber;

	if (decision.decision === 'returned') return { state: current ? 'returned' : 'resent', decision };
	if (current) return { state: 'accepted', decision };

	const accepted = input.answersOf(decision.submission_number);
	const same =
		accepted !== undefined && sameSectionAnswers(input.factKeys, accepted, input.newestAnswers);
	return { state: same ? 'accepted' : 'changed', decision };
}
