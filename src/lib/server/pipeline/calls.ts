import { databaseError, notFound, validationError } from '$lib/server/api/errors';

// A card's Brief lists its most recent calls. Ten is a screenful; older ones stay in the table.
export const CALL_LOG_LIMIT = 10;

export const CALL_LOG_COLUMNS = 'id, opportunity_id, outcome, note, logged_by, created_at';

export type CallLogRow = {
	id: string;
	opportunity_id: string;
	outcome: string;
	note: string | null;
	logged_by: string | null;
	created_at: string;
};

export function toCallLog(row: CallLogRow) {
	return {
		id: row.id,
		opportunity_id: row.opportunity_id,
		outcome: row.outcome,
		note: row.note,
		logged_by: row.logged_by,
		created_at: row.created_at
	};
}

// A refusal comes back as a plain not-found: the database gives the same answer whether the card is missing
// or belongs to somebody else, and the route must not undo that by being more specific.
export function callWriteError(error: { code?: string; message?: string }) {
	if (error.code === '42501') return notFound('That card could not be found.');
	if (error.code === '23514') {
		return validationError({ outcome: error.message ?? 'Choose what happened on the call.' });
	}
	return databaseError();
}
