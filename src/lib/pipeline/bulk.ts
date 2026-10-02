// The Table's bulk tools (plan § First-release board): change owner, add a Task, or place cards in a custom
// follow-up stage. Nothing else is offered in bulk — sending, converting, closing, and protected-stage moves
// stay one card at a time.

// The database's own ceiling for one bulk change (`pipeline_bulk_update`).
export const BULK_CARD_LIMIT = 50;

export type BulkAction = 'owner' | 'task' | 'place';

// One card's answer. `refused` carries the single-card path's own sentence; `code` is set only for the
// refusal the board can do something about (`needs_future_task`).
export type BulkCardResult =
	| { id: string; status: 'done' | 'unchanged' }
	| { id: string; status: 'refused'; reason: string; code: string | null };

export type BulkSummary = {
	done: number;
	unchanged: number;
	// The cards that were refused, kept so the table can leave just those selected.
	refusedIds: string[];
	// Each distinct reason once, with how many cards gave it, most common first.
	reasons: { reason: string; count: number }[];
};

export function summarizeBulk(results: readonly BulkCardResult[]): BulkSummary {
	const counts = new Map<string, number>();
	const refusedIds: string[] = [];
	let done = 0;
	let unchanged = 0;
	for (const result of results) {
		if (result.status === 'done') done += 1;
		else if (result.status === 'unchanged') unchanged += 1;
		else if (result.status === 'refused') {
			refusedIds.push(result.id);
			counts.set(result.reason, (counts.get(result.reason) ?? 0) + 1);
		}
	}
	const reasons = [...counts]
		.map(([reason, count]) => ({ reason, count }))
		.sort((a, b) => b.count - a.count);
	return { done, unchanged, refusedIds, reasons };
}

export const cardCount = (count: number) => `${count} ${count === 1 ? 'card' : 'cards'}`;
