// Two clocks on every card, kept in one place so the card and the Brief can never disagree.
//
// - Time in the column (`stage_entered_at`) is plain context. It never turns a card red by itself.
// - The inactivity warning counts from the card's last real progress (`progress_at`) and appears once that
//   is older than its stage's number of days — Pipedrive's "rotting" deal, with the plan's defaults
//   (docs/sales-pipeline-behavior-contract.md, § First-release board).
//
// The clock is the browser's. Both are elapsed time, not calendar dates, so the organization's timezone does
// not come into them — only an on-hold card's Task date is a calendar date, read against the organization's
// today.

import {
	isAnyBoardStage,
	type AnyBoardStage,
	type CustomStage,
	type OpportunityStage
} from './stages';

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

// How many days without progress each built-in stage allows before the warning: the plan's defaults, which
// an owner changes in Settings → Pipeline. A custom stage carries its own days.
export type InactivityDays = Record<AnyBoardStage, number>;

// The range an owner may set, in whole days. The database checks the same.
export const INACTIVITY_DAYS_MAX = 365;

export const DEFAULT_INACTIVITY_DAYS: InactivityDays = {
	new_request: 1,
	assessment_unscheduled: 2,
	assessment_scheduled: 2,
	assessment_completed: 2,
	quote_draft: 2,
	quote_awaiting_response: 5,
	quote_changes_requested: 2
};

// What the board knows that a card does not: the owner's days, the custom stages, and today's date in the
// organization's calendar (`YYYY-MM-DD`), which an on-hold card's Task date is measured against.
export type InactivityRules = {
	days: InactivityDays;
	customStages: readonly CustomStage[];
	today: string;
};

export type Inactivity = {
	/** Whole days since the last real progress. */
	days: number;
	/** `No progress for 3 days`. */
	label: string;
};

type InactivityCard = {
	stage: OpportunityStage;
	custom_stage_id: string | null;
	progress_at: string;
	// The card's earliest open Task.
	task: { due_on: string | null } | null;
};

// Null while the card is within its stage's days, while it waits on hold for its Task to fall due, while
// the board's rules have not arrived, or when it is not on the board at all.
export function inactivity(
	card: InactivityCard,
	rules: InactivityRules | null,
	now: number = Date.now()
): Inactivity | null {
	if (!rules || !isAnyBoardStage(card.stage)) return null;

	// A card whose custom stage has just been switched off is judged by its real stage until the board
	// catches up.
	const custom = card.custom_stage_id
		? rules.customStages.find((stage) => stage.id === card.custom_stage_id)
		: undefined;

	// On hold: quiet until the Task somebody promised to come back with falls due. From that day it counts
	// like any other card, from its last real progress.
	const dueOn = card.task?.due_on;
	if (custom?.requires_future_task && dueOn && dueOn > rules.today) return null;

	const allowed = custom?.inactivity_days ?? rules.days[card.stage];
	const elapsed = elapsedSince(card.progress_at, now);
	if (elapsed < allowed * DAY) return null;

	const days = Math.floor(elapsed / DAY);
	return { days, label: `No progress for ${days} ${days === 1 ? 'day' : 'days'}` };
}
