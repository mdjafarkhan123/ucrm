import { json } from '@sveltejs/kit';
import { databaseError, notFound } from '$lib/server/api/errors';

// A Brief Note as the Pipeline-scoped RPCs answer it: one note plus the single link that put it on this
// opportunity's Request, Quote or Client. The generic collaboration `Note` carries an array of links because one
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
	entity_type: 'request' | 'quote' | 'client';
	entity_id: string;
	files: PipelineNoteFile[];
	mention_user_ids: string[];
};

// A photo or file on a Note. Only ones still being checked or ready are listed; a pending one cannot be
// opened yet.
export type PipelineNoteFile = {
	id: string;
	display_name: string;
	mime_type: string;
	kind: 'image' | 'video' | 'document';
	size_bytes: number;
	has_thumbnail: boolean;
	processing_state: 'pending' | 'available';
};

const NOT_FOUND = 'That note is not on this opportunity.';

// The four Pipeline note functions refuse in the same two ways: `pipeline_note_scope` raises
// insufficient_privilege for a missing/foreign opportunity or a missing permission, and the entity-type
// guard in create raises check_violation. Same "one answer either way" reasoning as the Task write path.
//
// Every check_violation these functions raise is written for a person (a wrong target, too many files, a
// file that cannot be added, someone mentioned who cannot see the Pipeline), so its words are the answer.
export function pipelineNoteWriteError(error: { code?: string; message?: string }) {
	if (error.code === '42501') return notFound(NOT_FOUND);
	if (error.code === '23514') {
		const message = error.message ?? 'Not allowed.';
		return json(
			{ error: message, field_errors: { [checkField(message)]: message } },
			{ status: 422 }
		);
	}
	return databaseError();
}

function checkField(message: string) {
	if (/mention/i.test(message)) return 'mention_user_ids';
	if (/file|photo/i.test(message)) return 'file_ids';
	return 'entity_type';
}

export function pipelineNoteNotFound() {
	return notFound(NOT_FOUND);
}
