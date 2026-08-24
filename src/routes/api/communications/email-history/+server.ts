import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { hasPermission } from '$lib/server/access/permission';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

const PAGE_SIZE = 50;

function readCursor(value: string | null) {
	if (!value) return null;
	const separator = value.lastIndexOf('|');
	if (separator < 1) return null;
	const createdAt = value.slice(0, separator);
	const id = value.slice(separator + 1);
	if (Number.isNaN(Date.parse(createdAt)) || !id) return null;
	return { createdAt, id };
}

export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return json(
			{ error: 'Authentication or organization membership required.' },
			{ status: 401, headers: PRIVATE_READ_HEADERS }
		);
	}

	let access;
	try {
		access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
	} catch (error) {
		console.error('Could not resolve inbox access.', error);
		return databaseError();
	}

	const canViewTeam = hasPermission(access, 'conversations.view_team');
	const canViewAssigned = hasPermission(access, 'conversations.view_assigned');
	if (!canViewTeam && !canViewAssigned) {
		return json(
			{ error: 'You do not have access to conversations.', reason: 'permission_denied' },
			{ status: 403, headers: PRIVATE_READ_HEADERS }
		);
	}

	// Assignment/follower records do not exist yet. Never show a staff member the whole tenant merely to
	// make My Inbox look populated; an honest empty response is the safe state until that model lands.
	if (!canViewTeam) {
		return json(
			{ emails: [], next_cursor: null, view: 'assigned' },
			{ headers: PRIVATE_READ_HEADERS }
		);
	}

	const organizationId = auth.organization.id;
	const search = event.url.searchParams.get('search')?.trim() ?? '';
	const cursor = readCursor(event.url.searchParams.get('cursor'));
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_inbox_read:${organizationId}:${auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 120
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'private, no-cache');
			return response;
		}
	} catch (error) {
		console.error('Could not rate-limit inbox access.', error);
		return databaseError();
	}
	let query = ownerClient
		.from('communication_delivery_intents')
		.select(
			'id, client_id, recipient_email, quote_id, subject, text_content, status, failure_message, created_at'
		)
		.eq('organization_id', organizationId)
		.order('created_at', { ascending: false })
		.order('id', { ascending: false });
	if (search) {
		const escaped = search.replace(/[\\%_]/g, (match) => `\\${match}`).replace(/"/g, '\\"');
		query = query.or(`subject.ilike."%${escaped}%",recipient_email.ilike."%${escaped}%"`);
	}
	if (cursor) {
		query = query
			.lte('created_at', cursor.createdAt)
			.or(
				`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
			);
	}

	const { data: rows, error } = await query.limit(PAGE_SIZE + 1);
	if (error) {
		console.error('Could not load operational email history.', error);
		return databaseError();
	}
	const page = (rows ?? []).slice(0, PAGE_SIZE);
	const clientIds = [...new Set(page.map((row) => row.client_id))];
	const { data: clients, error: clientsError } = clientIds.length
		? await ownerClient
				.from('clients')
				.select('id, display_name')
				.eq('organization_id', organizationId)
				.in('id', clientIds)
		: { data: [], error: null };
	if (clientsError) return databaseError();
	const namesById = new Map((clients ?? []).map((client) => [client.id, client.display_name]));
	const last = page.at(-1);

	return json(
		{
			emails: page.map((row) => ({
				...row,
				client_name: namesById.get(row.client_id) ?? 'Client unavailable',
				client_email: row.recipient_email
			})),
			next_cursor: rows && rows.length > PAGE_SIZE && last ? `${last.created_at}|${last.id}` : null,
			view: 'team'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
