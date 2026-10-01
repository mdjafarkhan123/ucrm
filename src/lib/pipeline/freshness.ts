// Two clocks on every card, kept in one place so the card and the Brief can never disagree.
//
// - Time in the column (`stage_entered_at`) is plain context. It never turns a card red by itself.
// - The inactivity warning counts from the card's last real progress (`progress_at`) and appears once that
//   is older than its stage's number of days — Pipedrive's "rotting" deal, with the plan's defaults
//   (docs/sales-pipeline-behavior-contract.md, § First-release board).
//
// The clock is the browser's. Both are elapsed time, not calendar dates, so the organization's timezone does
// not come into it.

import type { OpportunityStage } from './stages';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

export type StageAge = {
	/** The short chip label: `0h`, `7h`, `21d`. */
	label: string;
	/** Said in full, for screen readers and the Brief. */
	description: string;
};

function elapsedSince(timestamp: string, now: number): number {
	const at = Date.parse(timestamp);
	// An unparseable or future timestamp reads as brand new rather than as a huge negative age.
	return Number.isNaN(at) ? 0 : Math.max(0, now - at);
}

export function stageAge(enteredAt: string, now: number = Date.now()): StageAge {
	const elapsed = elapsedSince(enteredAt, now);

	if (elapsed < HOUR) {
		return { label: '0h', description: 'In this stage for less than an hour' };
	}

	if (elapsed < DAY) {
		const hours = Math.floor(elapsed / HOUR);
		return {
			label: `${hours}h`,
			description: `In this stage for ${hours} ${hours === 1 ? 'hour' : 'hours'}`
		};
	}

	const days = Math.floor(elapsed / DAY);
	return {
		label: `${days}d`,
		description: `In this stage for ${days} ${days === 1 ? 'day' : 'days'}`
	};
}

// How many days without progress each protected stage allows before the warning. A card sitting in a custom
// stage is judged by its real stage until owners can set their own days (part C3).
export const INACTIVITY_DAYS: Record<Exclude<OpportunityStage, 'request_closed'>, number> = {
	new_request: 1,
	assessment_unscheduled: 2,
	assessment_scheduled: 2,
	assessment_completed: 2,
	quote_draft: 2,
	quote_awaiting_response: 5,
	quote_changes_requested: 2
};

export type Inactivity = {
	/** Whole days since the last real progress. */
	days: number;
	/** `No progress for 3 days`. */
	label: string;
};

// Null while the card is within its stage's days, or when it is not on the board at all.
export function inactivity(
	stage: OpportunityStage,
	progressAt: string,
	now: number = Date.now()
): Inactivity | null {
	if (stage === 'request_closed') return null;
	const elapsed = elapsedSince(progressAt, now);
	if (elapsed < INACTIVITY_DAYS[stage] * DAY) return null;

	const days = Math.floor(elapsed / DAY);
	return { days, label: `No progress for ${days} ${days === 1 ? 'day' : 'days'}` };
}
