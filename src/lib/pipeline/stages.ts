// The board's stage vocabulary, in one place the server and the browser both read. The database owns
// which stage a card is in — these names only say which stages exist and what a contractor calls them.
// `request_closed` is stored but never a column: completed, converted, and archived Requests keep their
// Opportunity and leave the board.
export const BOARD_STAGES = [
	'new_request',
	'assessment_unscheduled',
	'assessment_scheduled',
	'assessment_completed'
] as const;

export const OPPORTUNITY_STAGES = [...BOARD_STAGES, 'request_closed'] as const;

export type BoardStage = (typeof BOARD_STAGES)[number];
export type OpportunityStage = (typeof OPPORTUNITY_STAGES)[number];

export const BOARD_STAGE_LABELS: Record<BoardStage, string> = {
	new_request: 'New requests',
	assessment_unscheduled: 'Assessment unscheduled',
	assessment_scheduled: 'Assessment scheduled',
	assessment_completed: 'Assessment completed'
};

export const OPPORTUNITY_OUTCOMES = ['open', 'won', 'lost'] as const;
export type OpportunityOutcome = (typeof OPPORTUNITY_OUTCOMES)[number];

export function isBoardStage(value: string): value is BoardStage {
	return (BOARD_STAGES as readonly string[]).includes(value);
}
