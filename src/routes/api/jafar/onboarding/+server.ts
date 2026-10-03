import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { clientOnboardingListQuerySchema } from '$lib/server/validation/client-onboarding-list.schema';
import {
	onboardingCatalogue,
	onboardingSetupSize,
	type OnboardingClient,
	type OnboardingListPage,
	type OnboardingTotals
} from '$lib/setup/onboarding-list';

type ListCursor = { account_created_at: string; id: string };

function encodeCursor(cursor: ListCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

function decodeCursor(value: string): ListCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (parsed && typeof parsed.account_created_at === 'string' && typeof parsed.id === 'string') {
			return parsed;
		}
		return null;
	} catch {
		return null;
	}
}

// Jafar's list of paid clients and how far each is through setup (client onboarding C1, plan §8). The
// task list lives in code, so it travels with the request and the database counts against today's version.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsed = clientOnboardingListQuerySchema.safeParse({
		search: event.url.searchParams.get('search') ?? undefined,
		waiting_on: event.url.searchParams.get('waiting_on') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined
	});
	if (!parsed.success)
		return json({ error: 'The client list filter is invalid.' }, { status: 422 });

	let cursor: ListCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_client_onboarding_list', {
		setup_catalogue: onboardingCatalogue() as Json,
		search_term: parsed.data.search || undefined,
		waiting_filter: parsed.data.waiting_on,
		cursor_account_created_at: cursor?.account_created_at,
		cursor_id: cursor?.id,
		page_size: parsed.data.limit ?? 50
	});
	if (error) {
		console.error('Could not list onboarding clients.', error);
		return json({ error: 'The client list could not be loaded.' }, { status: 500 });
	}

	const result = data as {
		clients: OnboardingClient[];
		next_cursor: ListCursor | null;
		totals: OnboardingTotals;
	};
	const page: OnboardingListPage = {
		clients: result.clients,
		next_cursor: result.next_cursor ? encodeCursor(result.next_cursor) : null,
		totals: result.totals,
		setup_size: onboardingSetupSize()
	};
	return json(page, { headers: { 'cache-control': 'private, no-cache' } });
};
