import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSetupCatalogue } from '$lib/server/setup/catalogue';
import { clientOnboardingListQuerySchema } from '$lib/server/validation/client-onboarding-list.schema';
import { projectState } from '$lib/setup/project-state';
import { todayIn } from '$lib/setup/ready';
import {
	onboardingCatalogue,
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
// published setup version travels with the request, so the database counts against the questions asked now.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsed = clientOnboardingListQuerySchema.safeParse({
		search: event.url.searchParams.get('search') ?? undefined,
		waiting_on: event.url.searchParams.get('waiting_on') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		delivered: event.url.searchParams.get('delivered') ?? undefined
	});
	if (!parsed.success)
		return json({ error: 'The client list filter is invalid.' }, { status: 422 });

	let cursor: ListCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	const client = getOwnerSupabaseClient();
	const catalogue = await readSetupCatalogue(client);
	if (!catalogue) return json({ error: 'The client list could not be loaded.' }, { status: 500 });

	const { data, error } = await client.rpc('owner_client_onboarding_list', {
		setup_catalogue: onboardingCatalogue(catalogue) as Json,
		search_term: parsed.data.search || undefined,
		waiting_filter: parsed.data.waiting_on,
		cursor_account_created_at: cursor?.account_created_at,
		cursor_id: cursor?.id,
		page_size: parsed.data.limit ?? 50,
		include_delivered: parsed.data.delivered ?? false
	});
	if (error) {
		console.error('Could not list onboarding clients.', error);
		return json({ error: 'The client list could not be loaded.' }, { status: 500 });
	}

	const result = data as {
		clients: Omit<OnboardingClient, 'next_section_title' | 'project_state'>[];
		next_cursor: ListCursor | null;
		totals: OnboardingTotals;
	};
	// E1: Ready turns into Building on the client's first business day after it, so the list needs each Ready
	// client's start date and time zone — one primary-key read for at most a page of clients.
	const readyIds = result.clients.filter((row) => row.ready_at).map((row) => row.id);
	const readyRows = new Map<
		string,
		{ submission_number: number; start_date: string; time_zone: string }
	>();
	if (readyIds.length > 0) {
		const ready = await client
			.from('organization_setup_ready')
			.select('organization_id, submission_number, start_date, time_zone')
			.in('organization_id', readyIds);
		if (ready.error) {
			console.error('Could not read Ready for Uplift dates.', ready.error);
			return json({ error: 'The client list could not be loaded.' }, { status: 500 });
		}
		for (const row of ready.data) readyRows.set(row.organization_id, row);
	}

	const page: OnboardingListPage = {
		clients: result.clients.map((row) => {
			const ready = readyRows.get(row.id);
			return {
				...row,
				next_section_title:
					catalogue.sections.find((section) => section.key === row.next_section_key)?.title ?? null,
				project_state: projectState({
					paid_at: row.account_created_at,
					first_sent_at: null,
					sent:
						row.sent_number && row.sent_at
							? { number: row.sent_number, submitted_at: row.sent_at }
							: null,
					returned_count: row.returned_count,
					ready:
						ready && row.target_from && row.target_to
							? {
									submission_number: ready.submission_number,
									start_date: ready.start_date,
									target_from: row.target_from,
									target_to: row.target_to
								}
							: null,
					preview:
						row.preview_version && row.preview_released_at
							? {
									version: row.preview_version,
									released_at: row.preview_released_at,
									notes_sent_at: row.preview_sent_at
								}
							: null,
					approval:
						row.approval_status === 'approved' && row.approval_version && row.approved_at
							? { version: row.approval_version, approved_at: row.approved_at }
							: null,
					handover: { live_at: row.live_at, delivered_at: row.delivered_at },
					today: todayIn(ready?.time_zone ?? 'UTC')
				})
			};
		}),
		next_cursor: result.next_cursor ? encodeCursor(result.next_cursor) : null,
		totals: result.totals
	};
	return json(page, { headers: { 'cache-control': 'private, no-cache' } });
};
