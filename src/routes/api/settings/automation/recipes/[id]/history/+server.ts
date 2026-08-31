import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Settings → Automation detail, History tab: what ONE recipe has done, newest first. `view`-gated and
// organization-scoped. The engine's truth lives in `private` with no contractor read path, so this reads a
// SAFE projection through the security-definer public.automation_recipe_history function — summaries only,
// never the enrollment context snapshot, event payload, message body, or any worker/lease column
// (docs/automation-behavior-contract.md § Query, index, and count). Cursor-paginated on (happened_at desc,
// id desc); the query stays off until the tab is revealed, per the prefetch-on-reveal rule.

const recipeIdSchema = z.string().uuid();
const PAGE_SIZE = 25;

type HistoryRow = {
	id: string;
	happened_at: string;
	outcome: string;
	detail: string | null;
	subject_type: string;
	subject_id: string;
	enrollment_state: string | null;
	customer_messages_sent: number | null;
};

function readCursor(raw: string | null) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const happenedAt = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (id.length === 0) return null;
	return { happenedAt, id };
}

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	const organizationId = check.auth.organization.id;
	const cursor = readCursor(event.url.searchParams.get('cursor'));

	// Ask for one more than the page so we know whether a next page exists without a second query.
	const { data, error } = await getOwnerSupabaseClient().rpc('automation_recipe_history', {
		p_organization_id: organizationId,
		p_recipe_id: recipeId.data,
		// Omitted on the first page (no cursor); the function defaults them to null.
		p_before_happened_at: cursor?.happenedAt,
		p_before_id: cursor?.id,
		p_limit: PAGE_SIZE + 1
	});
	if (error) return databaseError();

	const rows = (data ?? []) as HistoryRow[];
	const page = rows.slice(0, PAGE_SIZE);
	const hasMore = rows.length > PAGE_SIZE;
	const last = page.at(-1);
	const nextCursor = hasMore && last ? `${last.happened_at}|${last.id}` : null;

	const entries = page.map((row) => ({
		id: row.id,
		happened_at: row.happened_at,
		outcome: row.outcome,
		detail: row.detail,
		subject_type: row.subject_type,
		subject_id: row.subject_id,
		enrollment_state: row.enrollment_state,
		customer_messages_sent: row.customer_messages_sent
	}));

	return json({ entries, next_cursor: nextCursor }, { headers: PRIVATE_READ_HEADERS });
};
