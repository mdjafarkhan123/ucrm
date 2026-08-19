import { databaseError, notFound, validationError } from '$lib/server/api/errors';

// A Brief Note as the Pipeline-scoped RPCs answer it: one note plus the single link that put it on this
// opportunity's Request or Client. The generic collaboration `Note` carries an array of links because one
// note can appear on more than one page; from the Brief a note only ever has the one link that matters here.
export type PipelineNoteRow = {
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

const NOT_FOUND = 'That note is not on this opportunity.';

// The four Pipeline note functions refuse in the same two ways: `pipeline_note_scope` raises
// insufficient_privilege for a missing/foreign opportunity or a missing permission, and the entity-type
// guard in create raises check_violation. Same "one answer either way" reasoning as the Task write path.
export function pipelineNoteWriteError(error: { code?: string; message?: string }) {
	if (error.code === '42501') return notFound(NOT_FOUND);
	if (error.code === '23514')
		return validationError({ entity_type: error.message ?? 'Not allowed.' });
	return databaseError();
}

export function pipelineNoteNotFound() {
	return notFound(NOT_FOUND);
}
