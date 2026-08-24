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

// The Quotes group's three board columns, added by Part 5A's stage derivation but not yet rendered by
// the board (that's Part 5C). Kept here, alongside the Requests vocabulary, because the drag transition
// table (Part 5B) already needs to validate against both groups.
export const QUOTE_BOARD_STAGES = [
	'quote_draft',
	'quote_awaiting_response',
	'quote_changes_requested'
] as const;

export const OPPORTUNITY_STAGES = [
	...BOARD_STAGES,
	...QUOTE_BOARD_STAGES,
	'request_closed'
] as const;

export type BoardStage = (typeof BOARD_STAGES)[number];
export type QuoteBoardStage = (typeof QUOTE_BOARD_STAGES)[number];
export type OpportunityStage = (typeof OPPORTUNITY_STAGES)[number];
// Every stage a column can actually render -- both groups, never the off-board `request_closed` parking
// value. Board-summary counts/totals and a column's own stage prop both speak this, not `OpportunityStage`.
export type AnyBoardStage = BoardStage | QuoteBoardStage;

export const BOARD_STAGE_LABELS: Record<BoardStage, string> = {
	new_request: 'New requests',
	assessment_unscheduled: 'Assessment unscheduled',
	assessment_scheduled: 'Assessment scheduled',
	assessment_completed: 'Assessment completed'
};

export const QUOTE_BOARD_STAGE_LABELS: Record<QuoteBoardStage, string> = {
	quote_draft: 'Draft',
	quote_awaiting_response: 'Awaiting response',
	quote_changes_requested: 'Changes requested'
};

// The collapsed Assessment column. A contractor sees one column called "Assessment"; the database still
// stores which of the three protected stages a card is really in. This is a presentation grouping only —
// no row is ever `stage = 'assessment'`, and nothing here changes what a stage means.
export const ASSESSMENT_GROUP = 'assessment';

export const ASSESSMENT_GROUP_STAGES = [
	'assessment_unscheduled',
	'assessment_scheduled',
	'assessment_completed'
] as const satisfies readonly BoardStage[];

// What a column can be asked for: any real stage, plus the one named logical column. Deliberately not
// "a list of stages" — the server maps this single name and refuses everything else, so no caller can
// invent a grouping the product has not approved.
export type BoardColumnKey = AnyBoardStage | typeof ASSESSMENT_GROUP;

export const BOARD_COLUMN_KEYS = [
	...BOARD_STAGES,
	...QUOTE_BOARD_STAGES,
	ASSESSMENT_GROUP
] as const satisfies readonly BoardColumnKey[];

export function isBoardColumnKey(value: string): value is BoardColumnKey {
	return (BOARD_COLUMN_KEYS as readonly string[]).includes(value);
}

// The one mapping both sides read: which stored stages a column is asking about. The server turns this
// into its predicate; the browser uses it to decide whether a card belongs to a column it is showing.
export function stagesInColumn(column: BoardColumnKey): readonly AnyBoardStage[] {
	return column === ASSESSMENT_GROUP ? ASSESSMENT_GROUP_STAGES : [column];
}

export function isAssessmentGroupStage(value: string): boolean {
	return (ASSESSMENT_GROUP_STAGES as readonly string[]).includes(value);
}

export const OPPORTUNITY_OUTCOMES = ['open', 'won', 'lost'] as const;
export type OpportunityOutcome = (typeof OPPORTUNITY_OUTCOMES)[number];

export function isBoardStage(value: string): value is BoardStage {
	return (BOARD_STAGES as readonly string[]).includes(value);
}

export function isQuoteBoardStage(value: string): value is QuoteBoardStage {
	return (QUOTE_BOARD_STAGES as readonly string[]).includes(value);
}

export function isAnyBoardStage(value: string): value is AnyBoardStage {
	return isBoardStage(value) || isQuoteBoardStage(value);
}

// One label lookup for anything that renders a stage name without caring which group it belongs to (the
// Brief's stage chip, a column header that already knows its own group from which array it looped over).
export const ALL_STAGE_LABELS: Record<AnyBoardStage, string> = {
	...BOARD_STAGE_LABELS,
	...QUOTE_BOARD_STAGE_LABELS
};

// Column headings. The collapsed column drops the sub-state from its name — the state lives on the card's
// own badge, not in the heading.
export const BOARD_COLUMN_LABELS: Record<BoardColumnKey, string> = {
	...ALL_STAGE_LABELS,
	[ASSESSMENT_GROUP]: 'Assessment'
};

// The board's own left-to-right column order for the Requests group, by presentation mode. The Quotes
// group never has a collapsed form -- its three stages have no protected sub-states to group.
export const REQUEST_COLUMNS_COLLAPSED: readonly BoardColumnKey[] = [
	'new_request',
	ASSESSMENT_GROUP
];
export const REQUEST_COLUMNS_DETAILED: readonly BoardColumnKey[] = [
	'new_request',
	...ASSESSMENT_GROUP_STAGES
];
export const QUOTE_COLUMNS: readonly BoardColumnKey[] = QUOTE_BOARD_STAGES;
