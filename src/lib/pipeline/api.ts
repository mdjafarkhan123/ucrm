import type { QueryClient } from '@tanstack/svelte-query';
import type { CustomerDeclineReason } from '$lib/quotes/customer-decline';
import type { BoardColumnKey, CustomStage, OpportunityOutcome, OpportunityStage } from './stages';
import type { BoardFormatting } from './money';
import type { InactivityDays } from './freshness';
import { boardFilterKey, boardFilterParams, type BoardFilters } from './filters';
import {
	outcomeFilterKey,
	outcomeFilterParams,
	type OutcomeFilters,
	type OutcomeType
} from './outcomes';
import type { DragActionKind } from './transitions';
import type { QuoteDeliveryFailure, QuoteSendChoice } from '$lib/quotes/send';

export type OpportunityCard = {
	id: string;
	title: string;
	// The real stage, decided by the Request, Assessment, or Quote behind the card.
	stage: OpportunityStage;
	// The custom follow-up stage somebody placed the card in, or null when it sits in its real stage.
	custom_stage_id: string | null;
	// When the card arrived in the column it is drawn in. The column shows its age from here, never from
	// created_at.
	stage_entered_at: string;
	// When the card last made real progress. The inactivity warning counts from here; a move between
	// custom stages does not restart it.
	progress_at: string;
	outcome: OpportunityOutcome;
	created_at: string;
	// Exactly one of `request`/`quote` is set -- the same single-source rule the database enforces on
	// opportunities.request_id/quote_id.
	request: { id: string; status: string } | null;
	// `delivery_failure` is set while the quote is awaiting a response and its latest email did not reach
	// the customer. The quote stays sent; this only says the customer has nothing yet.
	quote: { id: string; status: string; delivery_failure: QuoteDeliveryFailure | null } | null;
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
	// The one open Task the card shows, in Jobber's priority order (earliest due, undated last, ties by
	// creation). Null when the Opportunity has no open Task.
	task: { id: string; title: string; due_on: string | null } | null;
	// The booked assessment, present only once one has been scheduled. The collapsed Assessment column
	// shows all three sub-states together, so a card that says "scheduled" has to say when.
	assessment: { starts_at: string; ends_at: string | null } | null;
};

export type BoardColumnPage = {
	// The protected column's name, or the custom stage's id.
	stage: string;
	opportunities: OpportunityCard[];
	// Null means this was the last page of the column.
	next_cursor: string | null;
};

export type BoardCounts = Record<BoardColumnKey, number>;

export type BoardSummary = BoardFormatting & {
	counts: BoardCounts;
	// Every card the board is showing, added up across both groups' columns.
	result_count: number;
	// Absent when this member may not see money. A column's total is null when nobody has estimated
	// anything in it, which is not the same as zero and is never shown as $0.00.
	value_totals?: Record<BoardColumnKey, number | null>;
	// Whether this member may see estimated values at all. The board hides every money control when
	// false, rather than showing empty ones.
	can_view_value: boolean;
	// Whether this member may assign, reassign, or clear a card's owner.
	can_edit: boolean;
	// Which board this organization shows: false is the five-column default with one Assessment column,
	// true expands it into the three protected stages. Presentation only — the counts are the same either
	// way. It rides on the summary because that is the query the board already holds and already refreshes,
	// so saving the setting changes the board without a reload.
	detailed_assessment_stages: boolean;
	// Days without real progress before each built-in stage's cards warn, as the owner set them.
	inactivity_days: InactivityDays;
	// The custom follow-up columns an owner or administrator added in Settings, in saved order.
	custom_stages: CustomStage[];
	// Each custom column's heading, by stage id. A card placed in a custom stage is counted here and not
	// under its real stage.
	custom_counts: Record<string, number>;
	// Absent when this member may not see money, on the same rule as `value_totals`.
	custom_value_totals?: Record<string, number | null>;
};

// One family, so anything that changes commercial work can clear the whole board with `['pipeline']`
// and nothing else. Columns are keyed separately from the counts: loading more cards in one column must
// not re-count the board, and re-counting must not throw away loaded cards.
//
// Both keys carry the filters, and this is not optional. The columns and the headings have to be answering
// about the same set of cards, and a key that ignored the filters would hand a filtered board the cached
// answer to an unfiltered question — cards for one salesperson under a count of everybody's.
export const pipelineKey = ['pipeline'] as const;
// `column` is a protected column's key, or a custom stage's column id from `boardColumnId`.
export const boardColumnKey = (column: string, filters: BoardFilters) =>
	['pipeline', 'board', column, boardFilterKey(filters)] as const;
export const boardCountsKey = (filters: BoardFilters) =>
	['pipeline', 'summary', boardFilterKey(filters)] as const;
// One Opportunity's Brief Tasks. Still under the `['pipeline']` family so `invalidatePipeline` reaches it
// too, but a Task write only ever needs to invalidate this one key — it never changes a card's stage,
// money, or owner, so there is no reason to re-fetch the board behind the Brief for it.
export const opportunityTasksKey = (opportunityId: string) =>
	['pipeline', 'tasks', opportunityId] as const;
// The board's Won/Lost tiles and the Sales Outcomes report both stay under the `['pipeline']` family, so
// the `invalidatePipeline` call every Lost/Reopen write already makes reaches them too -- neither needs a
// write path of its own to invalidate.
export const outcomeTilesKey = ['pipeline', 'outcomes', 'tiles'] as const;
export const outcomesListKey = (filters: OutcomeFilters) =>
	['pipeline', 'outcomes', 'list', outcomeFilterKey(filters)] as const;

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

// `stage` is a protected column's name or a custom stage's id — `boardColumnRequestKey` gives either.
export async function fetchBoardColumn(
	stage: string,
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

// One tile's numbers. `value_total` is absent, not zero, for a member without `pipeline.view_value`.
export type OutcomeTile = { count: number; value_total?: number | null };

export type OutcomeTiles = {
	won: OutcomeTile;
	lost: OutcomeTile;
	can_view_value: boolean;
} & BoardFormatting;

export async function fetchOutcomeTiles(): Promise<OutcomeTiles> {
	const response = await fetch('/api/pipeline/outcomes/summary');
	if (!response.ok) throw await readError(response, 'The outcome totals could not be loaded.');
	return response.json();
}

// One row of the Sales Outcomes report -- Title, Client, Created At, Outcome date and Total, matching
// Jobber's own report columns. A Direct job row is `won`; the page's `type` says which list it is in. `estimated_value` is absent, not zero, for a member without
// `pipeline.view_value`.
export type OutcomeRow = {
	id: string;
	title: string;
	outcome: 'won' | 'lost';
	created_at: string;
	outcome_at: string;
	client: { id: string; display_name: string; company_name: string | null } | null;
	estimated_value?: number | null;
	// What closed: a Request, a Quote, or a Job booked with neither.
	source: 'request' | 'quote' | 'job';
	quote: { id: string; quote_number: number | null } | null;
	// Lost rows only. `reason` and `note` are the team's own classification and may be set afterwards;
	// `customer_declined` says the customer turned the quote down themselves, and `customer_message` is
	// what they said when they did.
	lost?: {
		reason: LostReason | null;
		note: string | null;
		customer_declined: boolean;
		customer_message: string | null;
		// What they picked when they declined from their quote link; null for a decline staff recorded.
		customer_reason: CustomerDeclineReason | null;
	};
	// Won rows only. A Won quote nobody has made a Job from can still be reopened; anything else is final.
	won?: { reopenable: boolean };
};

export type OutcomePage = {
	type: OutcomeType;
	outcomes: OutcomeRow[];
	// Null means this was the last page. Keyset paginated, the same as every other Pipeline list.
	next_cursor: string | null;
	// Whether Total and Client are even offerable as sorts, asked once rather than guessed from a row.
	can_view_value: boolean;
	can_view_clients: boolean;
	// Whether this member may reopen a Lost record or set its reason.
	can_edit: boolean;
};

export async function fetchOutcomes(
	filters: OutcomeFilters,
	cursor?: string
): Promise<OutcomePage> {
	const params = outcomeFilterParams(filters);
	// The type is always required by the route even at its default, unlike the rest of the filters --
	// a bare `type=` with nothing else would otherwise mean "leave it out because it is the default", and
	// the report has no sensible way to ask for "every type at once".
	params.set('type', filters.type);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/pipeline/outcomes?${params.toString()}`);
	if (!response.ok) throw await readError(response, 'The outcomes report could not be loaded.');
	return response.json();
}

// Requests and Assessments decide where cards sit, so their writes move the board too. Every one of them
// calls this rather than guessing which column changed — the stage is derived in the database, and the
// browser cannot know the answer before it re-reads.
export function invalidatePipeline(queryClient: QueryClient) {
	return queryClient.invalidateQueries({ queryKey: pipelineKey });
}

// One PATCH to one opportunity field route, sharing the fetch/error shape every Brief field edit needs.
async function patchOpportunityField<T>(
	opportunityId: string,
	segment: string,
	body: Record<string, unknown>,
	fallback: string
): Promise<T> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/${segment}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	if (!response.ok) throw await readError(response, fallback);
	return response.json();
}

// The card's ownership action. `null` clears ownership. Eligibility for a real id is enforced by the
// database trigger, not here — a refusal comes back as the same field error the form would raise itself.
export function assignOpportunityOwner(
	opportunityId: string,
	ownerUserId: string | null
): Promise<{ id: string; owner_user_id: string | null }> {
	return patchOpportunityField(
		opportunityId,
		'owner',
		{ owner_user_id: ownerUserId },
		'The owner could not be updated.'
	);
}

// The Brief's estimated value edit. `null` clears the estimate — never the same as a zero someone typed.
export function updateOpportunityValue(
	opportunityId: string,
	estimatedValue: number | null
): Promise<{ id: string; estimated_value: number | null }> {
	return patchOpportunityField(
		opportunityId,
		'value',
		{ estimated_value: estimatedValue },
		'The estimated value could not be updated.'
	);
}

// The Brief's expected close date edit. `null` clears the date.
export function updateOpportunityExpectedClose(
	opportunityId: string,
	expectedCloseOn: string | null
): Promise<{ id: string; expected_close_on: string | null }> {
	return patchOpportunityField(
		opportunityId,
		'expected-close',
		{ expected_close_on: expectedCloseOn },
		'The expected close date could not be updated.'
	);
}

// A Brief Task, as the client holds it. Mirrors the server's `toTask` field for field, so a create/edit
// response can replace a cached row without reshaping it.
export type Task = {
	id: string;
	opportunity_id: string;
	title: string;
	instructions: string | null;
	assignee_user_id: string | null;
	due_on: string | null;
	status: 'open' | 'completed';
	completed_at: string | null;
	completed_by: string | null;
	created_at: string;
};

export type TaskList = { open: Task[]; completed: Task[] };

export type TaskInput = {
	title: string;
	instructions: string | null;
	assignee_user_id: string | null;
	due_on: string | null;
};

// A Task write that fails for a reason the form can show: a bad field, the five-open/five-completed
// limit written for a person, or an assignee who cannot be given pipeline work. Anything else throws a
// plain Error with a message worth showing.
export class TaskWriteError extends Error {
	fieldErrors: Record<string, string>;

	constructor(message: string, fieldErrors: Record<string, string>) {
		super(message);
		this.name = 'TaskWriteError';
		this.fieldErrors = fieldErrors;
	}
}

async function taskWriteResult(response: Response, fallback: string): Promise<Task> {
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new TaskWriteError(result.error ?? fallback, result.field_errors ?? {});
	return result as Task;
}

export async function fetchOpportunityTasks(opportunityId: string): Promise<TaskList> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/tasks`);
	if (!response.ok) throw await readError(response, 'The tasks could not be loaded.');
	return response.json();
}

export function createTask(opportunityId: string, input: TaskInput): Promise<Task> {
	return fetch(`/api/pipeline/opportunities/${opportunityId}/tasks`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	}).then((response) => taskWriteResult(response, 'That task could not be created.'));
}

export function updateTask(taskId: string, input: TaskInput): Promise<Task> {
	return fetch(`/api/pipeline/tasks/${taskId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	}).then((response) => taskWriteResult(response, 'That task could not be saved.'));
}

// Completing and reopening are the same request with the flag turned around, mirroring the route.
export function setTaskCompletion(taskId: string, completed: boolean): Promise<Task> {
	return fetch(`/api/pipeline/tasks/${taskId}/completion`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ completed })
	}).then((response) => taskWriteResult(response, 'That task could not be updated.'));
}

export async function deleteTask(taskId: string): Promise<{ id: string; opportunity_id: string }> {
	const response = await fetch(`/api/pipeline/tasks/${taskId}`, { method: 'DELETE' });
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new TaskWriteError(
			result.error ?? 'That task could not be removed.',
			result.field_errors ?? {}
		);
	}
	return result;
}

// --- Brief Notes -------------------------------------------------------------------------------------------

// One Note as the Pipeline-scoped route answers it: the note plus the single link that put it on this
// opportunity's Request or Client. Authorized by pipeline.edit even for a Client target -- the generic
// `$lib/collaboration/api` Notes calls stay on their own customers.edit/property.manage contract and are
// not used here.
export type PipelineNote = {
	id: string;
	body: string;
	pinned: boolean;
	created_by: string | null;
	edited_by: string | null;
	edited_at: string | null;
	created_at: string;
	updated_at: string;
	entity_type: 'request' | 'client';
	entity_id: string;
};

// Its own key, not nested under a Task-style opportunity family entry: a Note never changes a card's
// stage, money, owner, or open Task, so nothing here ever needs `invalidatePipeline`.
export const opportunityNotesKey = (opportunityId: string) =>
	['pipeline', 'notes', opportunityId] as const;

export class NoteWriteError extends Error {
	fieldErrors: Record<string, string>;

	constructor(message: string, fieldErrors: Record<string, string>) {
		super(message);
		this.name = 'NoteWriteError';
		this.fieldErrors = fieldErrors;
	}
}

async function noteWriteResult<T>(response: Response, fallback: string): Promise<T> {
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new NoteWriteError(result.error ?? fallback, result.field_errors ?? {});
	return result as T;
}

export async function fetchOpportunityNotes(opportunityId: string): Promise<PipelineNote[]> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/notes`);
	if (!response.ok) throw await readError(response, 'The notes could not be loaded.');
	const { notes } = (await response.json()) as { notes: PipelineNote[] };
	return notes;
}

export function createOpportunityNote(
	opportunityId: string,
	input: { entityType: 'request' | 'client'; body: string }
): Promise<PipelineNote> {
	return fetch(`/api/pipeline/opportunities/${opportunityId}/notes`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ entity_type: input.entityType, body: input.body })
	}).then((response) =>
		noteWriteResult<{ note: PipelineNote }>(response, 'That note could not be created.').then(
			(result) => result.note
		)
	);
}

export function updateOpportunityNote(
	opportunityId: string,
	noteId: string,
	body: string
): Promise<PipelineNote> {
	return fetch(`/api/pipeline/opportunities/${opportunityId}/notes/${noteId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ body })
	}).then((response) =>
		noteWriteResult<{ note: PipelineNote }>(response, 'That note could not be saved.').then(
			(result) => result.note
		)
	);
}

// --- Outcomes -----------------------------------------------------------------------------------------

// The organization's own lost reasons (Settings → Pipeline). A Lost record stores a reason's key. Retired
// reasons are still listed, because old records carry them, but they are not offered for new choices.
// Leaving the reason unselected is valid.
export type LostReason = string;

export type LostReasonOption = {
	key: LostReason;
	label: string;
	is_built_in: boolean;
	retired_at: string | null;
};

export const lostReasonsKey = ['pipeline', 'lost-reasons'] as const;

export async function fetchLostReasons(): Promise<LostReasonOption[]> {
	const response = await fetch('/api/pipeline/lost-reasons');
	if (!response.ok) throw await readError(response, 'Lost reasons could not be loaded.');
	return ((await response.json()) as { reasons: LostReasonOption[] }).reasons;
}

// What a record's reason reads as. An unknown key shows as it is rather than vanishing.
export function lostReasonLabel(reasons: LostReasonOption[] | undefined, key: string | null) {
	if (!key) return null;
	return reasons?.find((reason) => reason.key === key)?.label ?? key;
}

export class LostReasonWriteError extends Error {
	fieldErrors: Record<string, string>;

	constructor(message: string, fieldErrors: Record<string, string>) {
		super(message);
		this.name = 'LostReasonWriteError';
		this.fieldErrors = fieldErrors;
	}
}

async function lostReasonWrite(response: Response, fallback: string): Promise<LostReasonOption> {
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		const fields = (result.field_errors ?? {}) as Record<string, string>;
		throw new LostReasonWriteError(fields.label ?? fields.form ?? result.error ?? fallback, fields);
	}
	return result.reason as LostReasonOption;
}

export function addLostReason(label: string): Promise<LostReasonOption> {
	return fetch('/api/settings/pipeline/lost-reasons', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ label })
	}).then((response) => lostReasonWrite(response, 'That reason could not be added.'));
}

export function setLostReasonRetired(key: string, retired: boolean): Promise<LostReasonOption> {
	return fetch(`/api/settings/pipeline/lost-reasons/${encodeURIComponent(key)}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ retired })
	}).then((response) => lostReasonWrite(response, 'That reason could not be changed.'));
}

export type OutcomeCommandResult = {
	applied: boolean;
	event_id: string;
	outcome: 'lost' | 'open';
	outcome_at: string | null;
};

export class OutcomeWriteError extends Error {
	fieldErrors: Record<string, string>;

	constructor(message: string, fieldErrors: Record<string, string>) {
		super(message);
		this.name = 'OutcomeWriteError';
		this.fieldErrors = fieldErrors;
	}
}

async function outcomeWriteResult(
	response: Response,
	fallback: string
): Promise<OutcomeCommandResult> {
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new OutcomeWriteError(result.error ?? fallback, result.field_errors ?? {});
	}
	return result as OutcomeCommandResult;
}

// Closes the card. A fresh idempotency key per dialog open means a retried submit after a dropped
// response is answered with the same result rather than a second event.
export function markOpportunityLost(
	opportunityId: string,
	input: { idempotencyKey: string; reason: LostReason | null; note: string | null }
): Promise<OutcomeCommandResult> {
	return fetch(`/api/pipeline/opportunities/${opportunityId}/lost`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			idempotency_key: input.idempotencyKey,
			reason: input.reason,
			note: input.note
		})
	}).then((response) => outcomeWriteResult(response, 'That opportunity could not be marked lost.'));
}

// Gives a record that is already Lost its reason, or changes it. Saving the same answer twice changes
// nothing, so there is no idempotency key to carry.
export async function setLostReason(
	opportunityId: string,
	input: { reason: LostReason | null; note: string | null }
): Promise<{ event_id: string; reason: LostReason | null; note: string | null }> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/lost-reason`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ reason: input.reason, note: input.note })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new OutcomeWriteError(
			result.error ?? 'That reason could not be saved.',
			result.field_errors ?? {}
		);
	}
	return result;
}

// Restores a Lost card, or a Won quote no Job has been made from. Its only entry point is a row's Reopen
// action in the Sales Outcomes report.
export function reopenOpportunity(
	opportunityId: string,
	input: { idempotencyKey: string; reopenExplanation: string }
): Promise<OutcomeCommandResult> {
	return fetch(`/api/pipeline/opportunities/${opportunityId}/reopen`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			idempotency_key: input.idempotencyKey,
			reopen_explanation: input.reopenExplanation
		})
	}).then((response) => outcomeWriteResult(response, 'That opportunity could not be reopened.'));
}

// --- Drag ----------------------------------------------------------------------------------------------

export type DragResult = {
	id: string;
	from_stage: OpportunityStage;
	to_stage: OpportunityStage;
	// Only the conversion drop answers with one, so the toast can name the quote it just created.
	quote?: { quote_id: string; quote_number: number; applied: boolean };
	// Present when this move is one the board may offer a short Undo for.
	undo?: { restore_new_request: boolean };
};

export class DragWriteError extends Error {
	fieldErrors: Record<string, string>;
	// Set for a refusal the board can help with rather than only report.
	code: string | null;

	constructor(message: string, fieldErrors: Record<string, string>, code: string | null = null) {
		super(message);
		this.name = 'DragWriteError';
		this.fieldErrors = fieldErrors;
		this.code = code;
	}
}

// An on-hold stage refused the card because it has no open Task due after today.
export const NEEDS_FUTURE_TASK = 'needs_future_task';

// Dropping a card onto a column. The server decides what that column requires and performs it first --
// this only carries the inputs a drop can need: the times a schedule drop asks for, and the key that
// makes a conversion safe to retry. `invalidatePipeline` still has to follow a success, the same as any
// other write that can move a card.
export async function dragOpportunity(
	opportunityId: string,
	input: {
		toStage: OpportunityStage;
		startsAt?: string;
		endsAt?: string;
		/** Required for the Draft conversion drop and an emailed quote. Keep it stable across a retry. */
		idempotencyKey?: string;
		/** Required for Draft -> Awaiting response: how the quote is going out, and the draft reviewed. */
		send?: QuoteSendChoice & { expectedRevision: number };
	}
): Promise<DragResult> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/move`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			to_stage: input.toStage,
			starts_at: input.startsAt ?? null,
			ends_at: input.endsAt ?? null,
			...(input.idempotencyKey ? { idempotency_key: input.idempotencyKey } : {}),
			...(input.send
				? {
						send:
							input.send.method === 'email'
								? { method: 'email', expected_revision: input.send.expectedRevision }
								: {
										method: 'external',
										expected_revision: input.send.expectedRevision,
										channel: input.send.channel,
										note: input.send.note
									}
					}
				: {})
		})
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		// A refusal written for a person arrives as the form's own error; the generic line is only for a
		// failure nobody can explain.
		throw new DragWriteError(
			result.field_errors?.form ?? result.error ?? 'That card could not be moved.',
			result.field_errors ?? {}
		);
	}
	return result as DragResult;
}

// Takes back a move the board has just made, while it is still the last thing that happened to the card.
// The refusal carries the database's own sentence.
export async function undoOpportunityMove(
	opportunityId: string,
	move: Pick<DragResult, 'from_stage' | 'to_stage'> & { undo: NonNullable<DragResult['undo']> }
): Promise<{ id: string; stage: OpportunityStage; custom_stage_id: string | null }> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/move/undo`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			from_stage: move.from_stage,
			to_stage: move.to_stage,
			restore_new_request: move.undo.restore_new_request
		})
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new DragWriteError(
			result.field_errors?.form ?? result.error ?? 'That move could not be undone.',
			result.field_errors ?? {}
		);
	}
	return result;
}

// Placing a card in a custom follow-up stage, or back in its real stage with `null`. Nothing about the
// Request or Quote changes. A refusal carries the database's own sentence — which section the card
// belongs to, or that the stage has gone — so the board can say exactly why. An on-hold stage's refusal
// also carries `NEEDS_FUTURE_TASK`, which the board answers by offering the Task.
export async function placeOpportunity(
	opportunityId: string,
	customStageId: string | null
): Promise<{
	id: string;
	stage: OpportunityStage;
	custom_stage_id: string | null;
	applied: boolean;
}> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/placement`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ custom_stage_id: customStageId })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new DragWriteError(
			result.field_errors?.form ?? result.error ?? 'That card could not be moved.',
			result.field_errors ?? {},
			typeof result.code === 'string' ? result.code : null
		);
	}
	return result;
}

// Takes back a placement the board just made. `customStageId` names it: where the card was put, or `null`
// when it was taken out of a custom stage. The server puts the card back with the time it had already
// spent there, and refuses once anything else has happened to the card.
export async function undoOpportunityPlacement(
	opportunityId: string,
	customStageId: string | null
): Promise<{ id: string; stage: OpportunityStage; custom_stage_id: string | null }> {
	const response = await fetch(`/api/pipeline/opportunities/${opportunityId}/placement/undo`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ custom_stage_id: customStageId })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new DragWriteError(
			result.field_errors?.form ?? result.error ?? 'That move could not be undone.',
			result.field_errors ?? {}
		);
	}
	return result;
}

// What kind of dialog a drop needs before it can run, if any -- re-exported here so a component importing
// the Pipeline API does not also need to reach into `./transitions` directly.
export type { DragActionKind };

export function deleteOpportunityNote(
	opportunityId: string,
	noteId: string,
	entityType: 'request' | 'client'
): Promise<{ unlinked: boolean; note_deleted: boolean }> {
	return fetch(`/api/pipeline/opportunities/${opportunityId}/notes/${noteId}`, {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ entity_type: entityType })
	}).then((response) => noteWriteResult(response, 'That note could not be removed.'));
}
