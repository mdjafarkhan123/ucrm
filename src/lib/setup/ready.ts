// Client onboarding C4: Ready for Uplift — the moment Uplift has what it needs and the 7–10 business-day build
// starts (plan §4–5, §10 journey 7). Jafar's choices of 2026-10-05: every task of the newest send accepted and
// every help request on a required question answered, a paused account or reversed payment blocks it, business
// days are Monday to Friday in the client's time zone, and a Ready pressed by mistake can be taken back with a
// reason. The database records Ready and fixes the dates (supabase/migrations/20261029090000_setup_ready_for_uplift.sql);
// the blockers are worked out here, from the same review and help reads both pages use.

import type { SetupHelpItem } from '$lib/setup/help';
import type { SetupReviewState, SetupSectionReview } from '$lib/setup/review';

export const SETUP_READY_DAYS = { from: 7, to: 10 } as const;
export const SETUP_READY_REASON_MAX = 500;

/** The current Ready for Uplift, as `organization_setup_ready` holds it. Dates are the client's own, `YYYY-MM-DD`. */
export type SetupReady = {
	submission_number: number;
	ready_at: string;
	ready_by_email: string;
	time_zone: string;
	start_date: string;
	target_from: string;
	target_to: string;
};

/** One thing that stops Ready for Uplift being recorded now. */
export type SetupReadyBlocker =
	| { kind: 'not_sent' }
	| { kind: 'account_paused' }
	| { kind: 'payment_reversed' }
	| {
			kind: 'task';
			section_key: string;
			section_title: string;
			state: Exclude<SetupReviewState, 'accepted'>;
	  }
	| { kind: 'help'; section_key: string; section_title: string; fact_key: string; label: string };

/**
 * Everything that stops Ready for Uplift on the newest send, in task order: the account, then each task not
 * accepted on it, then each open help request on a required question. Empty means Ready can be recorded.
 */
export function setupReadyBlockers(input: {
	account: { paused: boolean; payment_reversed: boolean };
	/** The newest send's tasks in order; null before the first send. */
	sections: readonly { key: string; title: string }[] | null;
	reviews: Readonly<Record<string, SetupSectionReview>>;
	help: readonly SetupHelpItem[];
}): SetupReadyBlocker[] {
	const blockers: SetupReadyBlocker[] = [];
	if (input.account.paused) blockers.push({ kind: 'account_paused' });
	if (input.account.payment_reversed) blockers.push({ kind: 'payment_reversed' });
	if (!input.sections) return [...blockers, { kind: 'not_sent' }];

	for (const section of input.sections) {
		const state = input.reviews[section.key]?.state ?? 'to_review';
		if (state !== 'accepted')
			blockers.push({
				kind: 'task',
				section_key: section.key,
				section_title: section.title,
				state
			});
	}
	for (const item of input.help)
		if (!item.answer && item.fact.required)
			blockers.push({
				kind: 'help',
				section_key: item.section_key,
				section_title: item.section_title,
				fact_key: item.fact_key,
				label: item.label
			});
	return blockers;
}

/** A blocker in words, for Jafar's Setup tab. */
export function setupReadyBlockerText(blocker: SetupReadyBlocker): string {
	switch (blocker.kind) {
		case 'not_sent':
			return 'The client has not sent their setup yet.';
		case 'account_paused':
			return 'The account is paused. Resume it first.';
		case 'payment_reversed':
			return 'Their payment was reversed. Settle it first.';
		case 'help':
			return `“${blocker.label}” in ${blocker.section_title}: the client asked for help. Add Uplift’s answer.`;
		case 'task':
			switch (blocker.state) {
				case 'to_review':
					return `${blocker.section_title}: not reviewed yet. Accept it or send it back.`;
				case 'returned':
					return `${blocker.section_title}: sent back. Waiting for the client to change it.`;
				case 'changed':
					return `${blocker.section_title}: the client changed it after you accepted it. Look again.`;
				case 'resent':
					return `${blocker.section_title}: the client sent it again after your send-back. Look again.`;
			}
	}
}

const toIso = (date: Date) => date.toISOString().slice(0, 10);

/**
 * The `days`-th Monday-to-Friday day after `from` (`YYYY-MM-DD`); public holidays are not skipped. Mirrors
 * `private.setup_add_business_days`, which fixes the dates the client sees; this one only previews them.
 */
export function addBusinessDays(from: string, days: number): string {
	const date = new Date(`${from}T00:00:00Z`);
	let counted = 0;
	while (counted < days) {
		date.setUTCDate(date.getUTCDate() + 1);
		const weekday = date.getUTCDay();
		if (weekday !== 0 && weekday !== 6) counted += 1;
	}
	return toIso(date);
}

/** Today's date in `timeZone`, as `YYYY-MM-DD`; an unknown zone counts in UTC, as the database does. */
export function todayIn(timeZone: string, now = new Date()): string {
	try {
		return new Intl.DateTimeFormat('en-CA', { timeZone }).format(now);
	} catch {
		return toIso(now);
	}
}

/** The range Ready would give if recorded now, for the confirmation before it is. */
export function previewSetupReadyRange(timeZone: string, now = new Date()) {
	const start = todayIn(timeZone, now);
	return {
		start_date: start,
		target_from: addBusinessDays(start, SETUP_READY_DAYS.from),
		target_to: addBusinessDays(start, SETUP_READY_DAYS.to)
	};
}

/** A `YYYY-MM-DD` date in words in the reader's own style, e.g. "Wednesday 14 October" — the same day wherever it is read. */
export function formatReadyDate(date: string, withYear = false): string {
	return new Date(`${date}T12:00:00Z`).toLocaleDateString(undefined, {
		weekday: 'long',
		day: 'numeric',
		month: 'long',
		...(withYear ? { year: 'numeric' } : {}),
		timeZone: 'UTC'
	});
}
