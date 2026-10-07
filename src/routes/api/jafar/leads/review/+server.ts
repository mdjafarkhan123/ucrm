import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { leadReviewQuerySchema } from '$lib/server/validation/lead.schema';
import type { ReviewQueuePage } from '$lib/jafar/lead-review';

// Jafar business management B3: the Leads ready for review, oldest first, one page at a time.

type ReviewCursor = { created_at: string; id: string };

function encodeCursor(cursor: ReviewCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

function decodeCursor(value: string): ReviewCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (
			parsed &&
			typeof parsed.created_at === 'string' &&
			!Number.isNaN(Date.parse(parsed.created_at)) &&
			typeof parsed.id === 'string' &&
			/^[0-9a-f-]{36}$/i.test(parsed.id)
		)
			return { created_at: parsed.created_at, id: parsed.id };
		return null;
	} catch {
		return null;
	}
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsed = leadReviewQuerySchema.safeParse({
		cursor: event.url.searchParams.get('cursor') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	let cursor: ReviewCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_review_queue', {
			cursor_created_at: cursor?.created_at,
			cursor_id: cursor?.id,
			page_size: 20
		});
		if (error) throw error;
		const result = data as unknown as Omit<ReviewQueuePage, 'next_cursor'> & {
			next_cursor: ReviewCursor | null;
		};
		return json(
			{
				leads: result.leads,
				next_cursor: result.next_cursor ? encodeCursor(result.next_cursor) : null,
				total: result.total
			} satisfies ReviewQueuePage,
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not load the review queue.', error);
		return json({ error: 'The review queue could not be loaded.' }, { status: 500 });
	}
};
