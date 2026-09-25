import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { embeddedOne } from '$lib/server/db/embedded';
import { createFileShareToken, fileShareUrl } from '$lib/server/files/share-links';
import { fileShareCreateSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Making one customer file share (behavior contract, "How a selected-file share works"). The token is made
// here, in Node, and the database is handed only its SHA-256, so the raw link exists exactly once: in this
// response, for the Copy link button.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = fileShareCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.share');
	if ('response' in access) return access.response;

	// Read under the caller's own policies: a share must not become a way to reach a Client or a File this
	// member could not otherwise see. Hidden and missing answer the same "not found".
	const [clientResult, filesResult] = await Promise.all([
		event.locals.supabase
			.from('clients')
			.select('id')
			.eq('id', parsed.data.client_id)
			.maybeSingle(),
		event.locals.supabase.from('files').select('id').in('id', parsed.data.file_ids)
	]);
	if (clientResult.error || filesResult.error) {
		console.error('Could not check a file share before making it.', {
			client: clientResult.error,
			files: filesResult.error
		});
		return databaseError();
	}
	if (!clientResult.data) return validationError({ client_id: 'That client was not found.' });
	if ((filesResult.data ?? []).length !== parsed.data.file_ids.length)
		return validationError({ file_ids: 'One of those files was not found.' });

	const { token, tokenHash } = createFileShareToken();
	const { data, error } = await getOwnerSupabaseClient().rpc('create_file_share', {
		target_organization_id: access.auth.organization.id,
		target_actor_id: access.auth.user.id,
		target_client_id: parsed.data.client_id,
		target_file_ids: parsed.data.file_ids,
		target_days: parsed.data.days,
		supplied_token_hash: tokenHash
	});
	if (error) {
		if (error.code === 'P0409') return validationError({ file_ids: error.message });
		if (error.code === 'P0002') return validationError({ client_id: 'That client was not found.' });
		console.error('Could not make a file share.', { code: error.code, message: error.message });
		return databaseError();
	}

	return json(
		{ share: data, url: fileShareUrl(event.url.origin, token) },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};

const PAGE_SIZE = 25;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Cursor format: "<issued_at>|<id>" -- issued_at alone is not unique, and a tie at a page boundary would
// drop or repeat a share. Anything malformed is treated as "first page" rather than trusted into a filter.
function readCursor(raw: string | null) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const issuedAt = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (!UUID_PATTERN.test(id) || Number.isNaN(Date.parse(issuedAt))) return null;
	return { issuedAt, id };
}

// The "Shared with customers" view: the organization's shares, newest first, whether they are live, expired
// or turned off. Read under the caller's own policies, which already limit it to files.share holders; the
// permission check first only turns a quiet empty list into an honest 403.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'files.share');
	if ('response' in access) return access.response;

	const cursor = readCursor(event.url.searchParams.get('cursor'));
	let query = event.locals.supabase
		.from('file_shares')
		.select(
			'id, client_id, issued_at, issued_by, expires_at, revoked_at, first_viewed_at, last_viewed_at, view_count, client:clients(display_name), items:file_share_items(count)'
		)
		.order('issued_at', { ascending: false })
		.order('id', { ascending: false })
		// One more than the page, so "is there another page" needs no second count query.
		.limit(PAGE_SIZE + 1);
	if (cursor) {
		query = query.or(
			`issued_at.lt."${cursor.issuedAt}",and(issued_at.eq."${cursor.issuedAt}",id.lt.${cursor.id})`
		);
	}

	const { data, error } = await query;
	if (error) {
		console.error('Could not list file shares.', error);
		return databaseError();
	}

	const rows = data ?? [];
	const hasMore = rows.length > PAGE_SIZE;
	const page = hasMore ? rows.slice(0, PAGE_SIZE) : rows;

	const issuerIds = [...new Set(page.map((row) => row.issued_by).filter((id) => id !== null))];
	const issuers = issuerIds.length
		? await event.locals.supabase.from('profiles').select('id, full_name').in('id', issuerIds)
		: { data: [], error: null };
	if (issuers.error) console.error('Could not name who made file shares.', issuers.error);
	const issuerNames = new Map((issuers.data ?? []).map((row) => [row.id, row.full_name]));

	const last = page.at(-1);
	return json(
		{
			shares: page.map((row) => ({
				id: row.id,
				client_id: row.client_id,
				// A Client this member may not see is still their share to manage; it is just not named.
				client_name: embeddedOne(row.client)?.display_name ?? null,
				file_count: row.items[0]?.count ?? 0,
				issued_at: row.issued_at,
				issued_by_name: row.issued_by ? (issuerNames.get(row.issued_by) ?? null) : null,
				expires_at: row.expires_at,
				revoked_at: row.revoked_at,
				first_viewed_at: row.first_viewed_at,
				last_viewed_at: row.last_viewed_at,
				view_count: row.view_count
			})),
			next_cursor: hasMore && last ? `${last.issued_at}|${last.id}` : null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
