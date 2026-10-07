import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readBody } from '$lib/server/jafar/lead-approval';
import { dealCommandResponse } from '$lib/server/jafar/deals';
import { dealBoardQuerySchema, dealStartSchema } from '$lib/server/validation/deal.schema';
import type { DealColumnPage } from '$lib/jafar/deals';

// Jafar business management B4: one board column, a page at a time, and starting a Deal for a business.

type DealCursor = { due_on: string | null; lost_at: string | null; id: string };

function encodeCursor(cursor: DealCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

function decodeCursor(value: string): DealCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (parsed && typeof parsed.id === 'string') return parsed;
		return null;
	} catch {
		return null;
	}
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const query = event.url.searchParams;
	const parsed = dealBoardQuerySchema.safeParse({
		stage: query.get('stage') ?? undefined,
		cursor: query.get('cursor') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The board column is invalid.' }, { status: 422 });

	let cursor: DealCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_deal_board', {
			target_stage: parsed.data.stage,
			cursor_due_on: cursor?.due_on ?? undefined,
			cursor_lost_at: cursor?.lost_at ?? undefined,
			cursor_id: cursor?.id
		});
		if (error) throw error;
		const result = data as unknown as Omit<DealColumnPage, 'next_cursor'> & {
			next_cursor: DealCursor | null;
		};
		return json(
			{
				deals: result.deals,
				next_cursor: result.next_cursor ? encodeCursor(result.next_cursor) : null
			} satisfies DealColumnPage,
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not load the Deals board.', error);
		return json({ error: 'These Deals could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const body = await readBody(event.request, dealStartSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_deal_start', {
		actor_email: session.email,
		target_relationship_id: body.data.relationship_id,
		target_stage: body.data.stage,
		target_next_action: body.data.next_action.text,
		target_due_on: body.data.next_action.due_on
	});
	return dealCommandResponse(result, 'start the Deal', 'This business no longer exists.');
};
