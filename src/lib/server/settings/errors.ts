import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

type CommandResult = {
	status?: string;
	editor_name?: string | null;
	edited_at?: string | null;
};

// The settings commands refuse in the same two ways, and each already carries the sentence a person
// should read. Anything else is ours to apologise for, not theirs to decode.
export function settingsWriteError(error: DatabaseError) {
	if (error.code === '42501')
		return json(
			{ error: 'You do not have access to change business settings.', reason: 'permission_denied' },
			{ status: 403 }
		);

	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That change is not allowed.' });

	return databaseError();
}

// Not a failure: two people had the page open. The command hands back who saved first and when, so the
// page can offer to look at their version rather than flattening it.
export function staleSettingsResponse(result: CommandResult) {
	return json(
		{
			error: 'Someone else changed these settings while you were editing.',
			reason: 'stale',
			editor_name: result.editor_name ?? null,
			edited_at: result.edited_at ?? null
		},
		{ status: 409, headers: NO_STORE_HEADERS }
	);
}

export function isStale(result: unknown): result is CommandResult {
	return (
		typeof result === 'object' && result !== null && (result as CommandResult).status === 'stale'
	);
}

// The tax rate commands (create/update/set-active/delete) refuse by raising rather than by returning a
// 'stale' result — 'settings.taxes.manage' is already checked at the route, so 42501 here only ever means
// the route's own check and the command's disagreed, which is a bug, not a normal refusal. The revision
// conflict is `P0409`, the same code every revision-protected command in the app uses — deliberately not
// `serialization_failure` (40001): PostgREST retries that one forever, since a stale revision never becomes
// current by retrying (see 20260902110000_stale_revision_conflicts_are_not_retryable.sql).
export function taxRateWriteError(error: DatabaseError) {
	if (error.code === '42501')
		return json(
			{ error: 'You do not have access to manage taxes.', reason: 'permission_denied' },
			{ status: 403 }
		);

	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'Someone else changed this tax rate while you were editing.',
				reason: 'stale'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);

	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That change is not allowed.' });

	return databaseError();
}
