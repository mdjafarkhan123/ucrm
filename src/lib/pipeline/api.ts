import type { QueryClient } from '@tanstack/svelte-query';
import type { BoardStage, OpportunityOutcome, OpportunityStage } from './stages';
import type { BoardFormatting } from './money';
import { boardFilterKey, boardFilterParams, type BoardFilters } from './filters';

export type OpportunityCard = {
	id: string;
	title: string;
	stage: OpportunityStage;
	// When the card arrived in this stage. The column shows its age from here, never from created_at.
	stage_entered_at: string;
	outcome: OpportunityOutcome;
	created_at: string;
	// Always present today. Null is reserved for the Quote-backed cards Part 5 adds.
	request: { id: string; status: string } | null;
	client: { id: string; display_name: string; company_name: string | null } | null;
	property: {
		id: string;
		label: string | null;
		address_line1: string;
		city: string;
		state_region: string | null;
		postal_code: string | null;
	} | null;
	// Null means unassigned. A name of null with an id means the owner has left the team: the card keeps
	// who owned it even when there is no longer a teammate to name.
	owner: { id: string; full_name: string | null; avatar_url: string | null } | null;
	// Absent when this member may not see money, and null when nobody has estimated the work yet. Never
	// zero for either of those — zero is a real estimate somebody typed.
	estimated_value?: number | null;
	expected_close_on: string | null;
	next_follow_up_on: string | null;
};

export type BoardColumnPage = {
	stage: BoardStage;
	opportunities: OpportunityCard[];
	// Null means this was the last page of the column.
	next_cursor: string | null;
};

export type BoardCounts = Record<BoardStage, number>;

export type BoardSummary = BoardFormatting & {
	counts: BoardCounts;
	// Every card the board is showing, added up across the four columns.
	result_count: number;
	// Absent when this member may not see money. A column's total is null when nobody has estimated
	// anything in it, which is not the same as zero and is never shown as $0.00.
	value_totals?: Record<BoardStage, number | null>;
	// Whether this member may see estimated values at all. The board hides every money control when
	// false, rather than showing empty ones.
	can_view_value: boolean;
};

// One family, so anything that changes commercial work can clear the whole board with `['pipeline']`
// and nothing else. Columns are keyed separately from the counts: loading more cards in one column must
// not re-count the board, and re-counting must not throw away loaded cards.
//
// Both keys carry the filters, and this is not optional. The columns and the headings have to be answering
// about the same set of cards, and a key that ignored the filters would hand a filtered board the cached
// answer to an unfiltered question — cards for one salesperson under a count of everybody's.
export const pipelineKey = ['pipeline'] as const;
export const boardColumnKey = (stage: BoardStage, filters: BoardFilters) =>
	['pipeline', 'board', stage, boardFilterKey(filters)] as const;
export const boardCountsKey = (filters: BoardFilters) =>
	['pipeline', 'summary', boardFilterKey(filters)] as const;

async function readError(response: Response, fallback: string) {
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		reason?: string;
	};
	const failure = new Error(result.error ?? fallback) as Error & {
		status?: number;
		reason?: string;
	};
	failure.status = response.status;
	failure.reason = result.reason;
	return failure;
}

export async function fetchBoardColumn(
	stage: BoardStage,
	filters: BoardFilters,
	cursor?: string
): Promise<BoardColumnPage> {
	const params = boardFilterParams(filters);
	params.set('stage', stage);
	// No cursor on the first page, and never a cursor from a different order — changing a control makes a
	// new query key, so paging starts again on its own rather than carrying a marker that means nothing here.
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/pipeline/opportunities?${params.toString()}`);
	if (!response.ok) throw await readError(response, 'That column could not be loaded.');
	return response.json();
}

export async function fetchBoardSummary(filters: BoardFilters): Promise<BoardSummary> {
	// The summary takes the same filters minus the ordering: a total does not care what order the cards
	// are in, and the route refuses to be asked for one.
	const params = boardFilterParams(filters);
	params.delete('sort');
	params.delete('direction');

	const query = params.toString();
	const response = await fetch(`/api/pipeline/summary${query ? `?${query}` : ''}`);
	if (!response.ok) throw await readError(response, 'The pipeline totals could not be loaded.');
	return response.json();
}

// Requests and Assessments decide where cards sit, so their writes move the board too. Every one of them
// calls this rather than guessing which column changed — the stage is derived in the database, and the
// browser cannot know the answer before it re-reads.
export function invalidatePipeline(queryClient: QueryClient) {
	return queryClient.invalidateQueries({ queryKey: pipelineKey });
}
