import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { historyRowFor, historyWriteError } from '$lib/server/jafar/lead-history';
import { leadHistoryEntrySchema } from '$lib/server/validation/lead.schema';

// Jafar business management B2: correcting or removing a note or logged contact. What the app recorded by
// itself -- status and next-action changes, linked Applications -- is never changed here: the queries below
// only match notes and logged contact, so anything else answers "not found".

const ENTRY_NOT_FOUND = 'This entry is no longer in the history.';

function validIds(params: { id: string; entryId: string }) {
	return z.uuid().safeParse(params.id).success && z.uuid().safeParse(params.entryId).success;
}

export const PATCH: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!validIds(event.params)) return notFound(ENTRY_NOT_FOUND);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadHistoryEntrySchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return validationError(fieldErrors);
	}

	// The kind cannot change: a note stays a note.
	const { kind, ...fields } = historyRowFor(parsed.data);
	try {
		const { data, error } = await getOwnerSupabaseClient()
			.from('platform_business_history')
			.update({ ...fields, edited_at: new Date().toISOString() })
			.eq('id', event.params.entryId)
			.eq('relationship_id', event.params.id)
			.eq('kind', kind)
			.select('id');
		if (error) {
			const refusal = historyWriteError(error);
			if (refusal) return refusal;
			throw error;
		}
		if (!data.length) return notFound(ENTRY_NOT_FOUND);
		return json({ ok: true });
	} catch (error) {
		console.error('Could not change the history entry.', error);
		return databaseError();
	}
};

export const DELETE: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!validIds(event.params)) return notFound(ENTRY_NOT_FOUND);

	try {
		const { data, error } = await getOwnerSupabaseClient()
			.from('platform_business_history')
			.delete()
			.eq('id', event.params.entryId)
			.eq('relationship_id', event.params.id)
			.in('kind', ['note', 'contact'])
			.select('id');
		if (error) throw error;
		if (!data.length) return notFound(ENTRY_NOT_FOUND);
		return json({ ok: true });
	} catch (error) {
		console.error('Could not delete the history entry.', error);
		return databaseError();
	}
};
