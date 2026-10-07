import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { leadCreateSchema, leadListQuerySchema } from '$lib/server/validation/lead.schema';
import type { LeadListPage } from '$lib/jafar/leads';

// Jafar business management B1: Uplift's Leads list, and adding a Lead.

type LeadCursor = { created_at: string; due_on: string; id: string };

function encodeCursor(cursor: LeadCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

function decodeCursor(value: string): LeadCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (
			parsed &&
			typeof parsed.created_at === 'string' &&
			typeof parsed.due_on === 'string' &&
			typeof parsed.id === 'string'
		)
			return parsed;
		return null;
	} catch {
		return null;
	}
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const query = event.url.searchParams;
	const parsed = leadListQuerySchema.safeParse({
		search: query.get('search') ?? undefined,
		status: query.get('status') ?? undefined,
		country: query.get('country') ?? undefined,
		source: query.get('source') ?? undefined,
		sort: query.get('sort') ?? undefined,
		deal: query.get('deal') ?? undefined,
		cursor: query.get('cursor') ?? undefined,
		limit: query.get('limit') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The Leads filter is invalid.' }, { status: 422 });

	let cursor: LeadCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	const filters = parsed.data;
	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_list', {
			search_term: filters.search || undefined,
			status_filter: filters.status,
			country_filter: filters.country,
			source_filter: filters.source,
			sort_order: filters.sort ?? 'newest',
			cursor_created_at: cursor?.created_at,
			cursor_due_on: cursor?.due_on,
			cursor_id: cursor?.id,
			page_size: filters.limit ?? 50,
			deal_filter: filters.deal === 'with' ? 'with' : 'without'
		});
		if (error) throw error;

		const result = data as unknown as Omit<LeadListPage, 'next_cursor'> & {
			next_cursor: LeadCursor | null;
		};
		return json(
			{
				leads: result.leads,
				next_cursor: result.next_cursor ? encodeCursor(result.next_cursor) : null,
				totals: result.totals
			} satisfies LeadListPage,
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not list Leads.', error);
		return json({ error: 'Leads could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadCreateSchema.safeParse(body);
	if (!parsed.success) {
		// `contact_methods.1.value` names the exact row, so the form can mark the right field.
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return validationError(fieldErrors);
	}

	const lead = parsed.data;
	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_create_lead', {
			target_business_name: lead.business_name,
			target_country_code: lead.country_code,
			target_trade: lead.trade,
			target_source: lead.source,
			target_source_detail: lead.source_detail ?? undefined,
			target_website: lead.website ?? undefined,
			target_contact_name: lead.contact_name ?? undefined,
			target_fit_notes: lead.fit_notes ?? undefined,
			target_lead_status: lead.lead_status,
			target_next_action: lead.next_action ?? undefined,
			target_next_action_due_on: lead.next_action_due_on ?? undefined,
			target_contact_methods: lead.contact_methods,
			actor_email: session.email
		});
		if (error) throw error;
		return json({ id: data }, { status: 201 });
	} catch (error) {
		console.error('Could not add the Lead.', error);
		return databaseError();
	}
};
