import type { OpportunityStage } from './stages';

// What a successful drop onto a stage actually does. `assessment_schedule` is the only one that needs the
// staff member to supply anything -- a start and end time -- before it can run; the rest complete on drop.
export type DragActionKind =
	| 'assessment_require'
	| 'assessment_schedule'
	| 'assessment_complete'
	| 'quote_convert'
	| 'quote_publish';

export const DRAG_ACTIONS_NEEDING_INPUT: readonly DragActionKind[] = ['assessment_schedule'];

// Moves that cannot be taken back and so are never performed on the drop alone. Converting creates a
// Quote and leaves the Request `converted`, which is terminal — there is no Undo to offer afterwards, so
// the browser asks first. Part 5D's Undo must not claim this one.
export const DRAG_ACTIONS_NEEDING_CONFIRMATION: readonly DragActionKind[] = ['quote_convert'];

type DragTransition = { to: OpportunityStage; action: DragActionKind };

// Forward-only, and only where a single existing domain command satisfies the target stage's entry rule
// in one step. This is a copy for the browser and the route to describe a move before asking; the
// database's `private.pipeline_drag_transition_allowed` is the actual gate and must agree with this list.
// Confirmed with Jafar 2026-08-23:
// - New requests -> Assessment completed is deliberately absent: it would need two commands (create the
//   assessment, then complete it), not one.
// - Awaiting response -> Changes requested is deliberately absent: only the client's own decision does
//   this. The card moves there by itself; staff cannot drag it there.
// - Changes requested has no forward drag target at all. Revise (-> Draft) and Republish
//   (-> Awaiting response) are real staff actions, but both are backward on the board, so they stay
//   Quote-page actions -- the card jumps back on its own once staff uses them, the same way un-completing
//   an assessment already moves a card backward today.
const DRAG_TRANSITIONS: Partial<Record<OpportunityStage, DragTransition[]>> = {
	new_request: [
		{ to: 'assessment_unscheduled', action: 'assessment_require' },
		{ to: 'assessment_scheduled', action: 'assessment_schedule' },
		{ to: 'quote_draft', action: 'quote_convert' }
	],
	assessment_unscheduled: [
		{ to: 'assessment_scheduled', action: 'assessment_schedule' },
		{ to: 'assessment_completed', action: 'assessment_complete' },
		{ to: 'quote_draft', action: 'quote_convert' }
	],
	// No path to Draft. A request with a booked visit is not convertible, which is why Draft is decided
	// card by card inside the collapsed Assessment column rather than once for the whole column.
	assessment_scheduled: [{ to: 'assessment_completed', action: 'assessment_complete' }],
	assessment_completed: [{ to: 'quote_draft', action: 'quote_convert' }],
	quote_draft: [{ to: 'quote_awaiting_response', action: 'quote_publish' }]
};

export function dragActionFor(from: OpportunityStage, to: OpportunityStage): DragActionKind | null {
	return DRAG_TRANSITIONS[from]?.find((transition) => transition.to === to)?.action ?? null;
}

export function allowedDragTargets(from: OpportunityStage): OpportunityStage[] {
	return (DRAG_TRANSITIONS[from] ?? []).map((transition) => transition.to);
}
