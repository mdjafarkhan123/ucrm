import { databaseError, notFound, validationError } from '$lib/server/api/errors';

// Jobber's limit, and the only reason a Task list needs no paging: an Opportunity can never hold more
// than five of each kind. The database enforces it; this is here so the read asks for no more than
// exists.
export const OPPORTUNITY_TASK_LIMIT = 5;

// Everything the Brief and the card actually show. The assignee is an id only -- the drawer already has
// the team list loaded for the owner control, so sending names again would be the same data twice.
export const TASK_COLUMNS =
	'id, opportunity_id, title, instructions, assignee_user_id, due_on, status, completed_at, completed_by, created_at';

export type TaskRow = {
	id: string;
	opportunity_id: string;
	title: string;
	instructions: string | null;
	assignee_user_id: string | null;
	due_on: string | null;
	status: string;
	completed_at: string | null;
	completed_by: string | null;
	created_at: string;
};

export function toTask(row: TaskRow) {
	return {
		id: row.id,
		opportunity_id: row.opportunity_id,
		title: row.title,
		instructions: row.instructions,
		assignee_user_id: row.assignee_user_id,
		due_on: row.due_on,
		status: row.status,
		completed_at: row.completed_at,
		completed_by: row.completed_by,
		created_at: row.created_at
	};
}

const NOT_FOUND = 'That task could not be found.';

// The four write functions refuse in the same three ways, so the answer is written once.
//
// A refusal comes back as a plain not-found on purpose: the database gives the same answer whether the
// record is missing or belongs to somebody else, and the route must not undo that by being more
// specific. The limit and the assignee check produce sentences a person can act on, so those are passed
// through as they are.
export function taskWriteError(error: { code?: string; message?: string }) {
	if (error.code === '42501') return notFound(NOT_FOUND);
	if (error.code === '54000')
		return validationError({ form: error.message ?? 'That is not allowed.' });
	// Zod has already rejected a bad title, an over-long instruction, and a malformed date, so the check
	// that is left in practice is the one saying this person cannot be given pipeline work.
	if (error.code === '23514') {
		return validationError({
			assignee_user_id: error.message ?? 'That person cannot be assigned.'
		});
	}
	return databaseError();
}

export function taskNotFound() {
	return notFound(NOT_FOUND);
}
