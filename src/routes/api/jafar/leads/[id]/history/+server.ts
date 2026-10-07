import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	decodeHistoryCursor,
	historyRowFor,
	historyWriteError,
	presentHistory,
	type RawHistoryPage
} from '$lib/server/jafar/lead-history';
import { leadHistoryEntrySchema, leadHistoryQuerySchema } from '$lib/server/validation/lead.schema';
import { HISTORY_PAGE_SIZE, type HistoryPage } from '$lib/jafar/lead-history';

// Jafar business management B2: older history for "Show older", and adding a note or logged contact. The page
// itself already carries the newest entries.

const LEAD_NOT_FOUND = 'This Lead no longer exists.';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const parsed = leadHistoryQuerySchema.safeParse({
		cursor: event.url.searchParams.get('cursor') ?? undefined
	});
	const cursor = parsed.success ? decodeHistoryCursor(parsed.data.cursor) : null;
	if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_history', {
			target_id: event.params.id,
			cursor_occurred_at: cursor.occurred_at,
			cursor_id: cursor.id,
			page_size: HISTORY_PAGE_SIZE
		});
		if (error) throw error;
		return json(presentHistory(data as unknown as RawHistoryPage) satisfies HistoryPage, {
			headers: PRIVATE_READ_HEADERS
		});
	} catch (error) {
		console.error('Could not load Lead history.', error);
		return json({ error: 'Older history could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

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

	try {
		const { data, error } = await getOwnerSupabaseClient()
			.from('platform_business_history')
			.insert({
				...historyRowFor(parsed.data),
				relationship_id: event.params.id,
				actor_email: session.email.trim().toLowerCase()
			})
			.select('id')
			.single();
		if (error) {
			const refusal = historyWriteError(error);
			if (refusal) return refusal;
			throw error;
		}
		return json({ id: data.id }, { status: 201 });
	} catch (error) {
		console.error('Could not add to the Lead history.', error);
		return databaseError();
	}
};
