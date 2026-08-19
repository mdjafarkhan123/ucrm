import { databaseError, notFound, validationError } from '$lib/server/api/errors';

const NOT_FOUND = 'That opportunity could not be found.';

// Lost and Reopen refuse in the same two ways every other Pipeline write function does: a missing or
// foreign opportunity and a missing permission come back as the same insufficient_privilege, and the RPC's
// own field-level guards (reason vocabulary, "Other" requiring a note, the explanation length, the
// five-task ceiling) come back as check_violation. Same "one answer either way" reasoning as
// `pipelineNoteWriteError`.
export function outcomeWriteError(error: { code?: string; message?: string }) {
	if (error.code === '42501') return notFound(NOT_FOUND);
	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That is not allowed.' });
	return databaseError();
}
