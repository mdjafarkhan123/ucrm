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

// The Table view's scope: every card the board draws, in one list. Asked for in place of a column, so the
// table pages through the same route, filters and orders as the columns do.
export const TABLE_SCOPE = 'all';

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

// Custom follow-up stages. An owner or administrator adds these in Settings → Pipeline; each belongs to
// one section for life and is stored with the protected stage it sits after, so the protected stages keep
// their own order and a section's first stage always stays first.
export const BOARD_SECTIONS = ['request', 'quote'] as const;
export type BoardSection = (typeof BOARD_SECTIONS)[number];

export const BOARD_SECTION_LABELS: Record<BoardSection, string> = {
	request: 'Requests',
	quote: 'Quotes'
};

// Jobber's documented ceiling for one pipeline.
export const CUSTOM_STAGE_LIMIT = 25;
export const CUSTOM_STAGE_NAME_MAX = 40;

export const SECTION_STAGES: Record<BoardSection, readonly AnyBoardStage[]> = {
	request: BOARD_STAGES,
	quote: QUOTE_BOARD_STAGES
};

export type CustomStage = {
	id: string;
	section: BoardSection;
	name: string;
	after_stage: AnyBoardStage;
	// An on-hold stage: a card may only be moved in while it has an open Task due after today.
	requires_future_task: boolean;
	// Days without real progress before a card here shows the inactivity warning.
	inactivity_days: number;
};

// Where a custom stage sits: its section, and the protected stage it follows. Settings works with stages
// that have no id yet, so the ordering below asks for nothing more than this.
type PlacedStage = Pick<CustomStage, 'section' | 'after_stage'>;

// A custom stage is asked for by its id wherever a protected column is asked for by its name: a column's
// page of cards, and the cursor that pages it.
const CUSTOM_STAGE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function isCustomStageId(value: string): boolean {
	return CUSTOM_STAGE_ID.test(value);
}

// Which side of the Request/Quote line a card is on, read off its real stage. Null once it has left the
// board. A card can only be placed in a custom stage of its own section.
export function stageSection(stage: OpportunityStage): BoardSection | null {
	if (isBoardStage(stage)) return 'request';
	if (isQuoteBoardStage(stage)) return 'quote';
	return null;
}

// One column on the board, or one row in the Settings list: a protected column, or a custom stage.
export type SectionColumn<T extends PlacedStage = CustomStage> =
	{ kind: 'protected'; key: BoardColumnKey } | { kind: 'custom'; stage: T };
export type BoardColumn = SectionColumn<CustomStage>;

export function boardColumnId(column: BoardColumn): string {
	return column.kind === 'protected' ? column.key : `custom-${column.stage.id}`;
}

// What the server is asked for to read a column's cards: the protected column's name, or the custom
// stage's id.
export function boardColumnRequestKey(column: BoardColumn): string {
	return column.kind === 'protected' ? column.key : column.stage.id;
}

function protectedColumns(section: BoardSection, detailed: boolean): readonly BoardColumnKey[] {
	if (section === 'quote') return QUOTE_COLUMNS;
	return detailed ? REQUEST_COLUMNS_DETAILED : REQUEST_COLUMNS_COLLAPSED;
}

// A section's columns, left to right. `customStages` arrives in its saved order; each stage is drawn
// straight after the protected column that holds the stage it follows. On the collapsed board that means
// a stage saved after any of the three assessment stages follows the one Assessment column.
export function sectionColumns<T extends PlacedStage>(
	section: BoardSection,
	detailed: boolean,
	customStages: readonly T[]
): SectionColumn<T>[] {
	const columns: SectionColumn<T>[] = [];
	for (const key of protectedColumns(section, detailed)) {
		columns.push({ kind: 'protected', key });
		for (const anchor of stagesInColumn(key)) {
			for (const stage of customStages) {
				if (stage.section === section && stage.after_stage === anchor) {
					columns.push({ kind: 'custom', stage });
				}
			}
		}
	}
	return columns;
}

// The reverse of `sectionColumns`, for Settings after a row has been moved: every custom stage takes the
// protected column above it as the stage it follows. The collapsed Assessment column stands for its last
// stage, which is where a stage placed after "Assessment" sits on the detailed board too.
export function placeCustomStages<T extends PlacedStage>(
	columns: readonly SectionColumn<T>[]
): T[] {
	const placed: T[] = [];
	let anchor: AnyBoardStage | null = null;
	for (const column of columns) {
		if (column.kind === 'protected') {
			anchor = stagesInColumn(column.key).at(-1) ?? null;
		} else if (anchor) {
			placed.push({ ...column.stage, after_stage: anchor });
		}
	}
	return placed;
}

// Whether the row at `index` may move one place up or down. Only custom rows move, and never above the
// section's first stage.
export function canMoveColumn<T extends PlacedStage>(
	columns: readonly SectionColumn<T>[],
	index: number,
	by: -1 | 1
): boolean {
	const target = index + by;
	return columns[index]?.kind === 'custom' && target >= 1 && target < columns.length;
}

export function moveColumn<T extends PlacedStage>(
	columns: readonly SectionColumn<T>[],
	index: number,
	by: -1 | 1
): SectionColumn<T>[] {
	if (!canMoveColumn(columns, index, by)) return [...columns];
	const next = [...columns];
	[next[index], next[index + by]] = [next[index + by], next[index]];
	return next;
}

// A custom stage may not borrow the name of a column already in its section — two "Draft" columns side by
// side cannot be told apart.
export function protectedNamesInSection(section: BoardSection): string[] {
	const names = SECTION_STAGES[section].map((stage) => ALL_STAGE_LABELS[stage]);
	return section === 'request' ? [...names, BOARD_COLUMN_LABELS[ASSESSMENT_GROUP]] : names;
}
