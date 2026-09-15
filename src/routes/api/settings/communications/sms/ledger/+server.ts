import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	safeSmsLedgerEntry,
	type SmsLedgerEntryRow
} from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

const PAGE_SIZE = 25;

const querySchema = z.object({
	limit: z.coerce.number().int().min(1).max(50).default(PAGE_SIZE),
	cursor: z.string().max(200).optional(),
	entry_kind: z.enum(['credit', 'charge', 'refund', 'adjustment']).optional(),
	since: z.iso.datetime().optional(),
	until: z.iso.datetime().optional()
});

function decodeCursor(raw: string | undefined) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const occurredAt = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (!id || Number.isNaN(Date.parse(occurredAt))) return null;
	return { occurredAt, id };
}

function encodeCursor(row: SmsLedgerEntryRow | undefined) {
	return row ? `${row.occurred_at}|${row.id}` : null;
}

// Stage 3D: the organization's own SMS credit ledger, reverse-chronological. Every row here is an immutable,
// already-posted entry (credit, charge, refund or adjustment) -- there is no separate "pending" ledger status
// to filter on; a reservation not yet settled shows in the balance strip's Reserved figure, not here.
// Cursor-paginated on (occurred_at desc, id desc), matching the table's own history index and the existing
// Team activity log pattern.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const parsed = querySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		entry_kind: event.url.searchParams.get('entry_kind') ?? undefined,
		since: event.url.searchParams.get('since') ?? undefined,
		until: event.url.searchParams.get('until') ?? undefined
	});
	if (!parsed.success) {
		return json({ error: 'That page link is invalid.' }, { status: 422, headers: noStore });
	}
	const cursor = decodeCursor(parsed.data.cursor);
	if (parsed.data.cursor && !cursor) {
		return json({ error: 'That page link is invalid.' }, { status: 422, headers: noStore });
	}

	let query = getOwnerSupabaseClient()
		.from('communication_sms_credit_ledger_entries')
		.select('id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at, reason')
		.eq('organization_id', check.auth.organization.id)
		.order('occurred_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(parsed.data.limit + 1);

	if (parsed.data.entry_kind) query = query.eq('entry_kind', parsed.data.entry_kind);
	if (parsed.data.since) query = query.gte('occurred_at', parsed.data.since);
	if (parsed.data.until) query = query.lt('occurred_at', parsed.data.until);
	if (cursor) {
		query = query.or(
			`occurred_at.lt.${cursor.occurredAt},and(occurred_at.eq.${cursor.occurredAt},id.lt.${cursor.id})`
		);
	}

	const { data, error } = await query;
	if (error) {
		console.error('Could not load the SMS credit ledger.', error);
		return json({ error: 'The ledger could not be loaded.' }, { status: 500, headers: noStore });
	}

	const rows = (data ?? []) as SmsLedgerEntryRow[];
	const page = rows.slice(0, parsed.data.limit);
	const hasMore = rows.length > parsed.data.limit;

	return json(
		{
			entries: page.map(safeSmsLedgerEntry),
			next_cursor: hasMore ? encodeCursor(page.at(-1)) : null
		},
		{ headers: noStore }
	);
};
