import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { embeddedOne } from '$lib/server/db/embedded';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// One share opened from "Shared with customers": its facts and its Files, in the order the customer sees
// them and under the names they were shared with. A File moved to Trash since is still listed, marked, so
// staff can see why the customer's page shows one fewer.
export const GET: RequestHandler = async (event) => {
	if (!UUID_PATTERN.test(event.params.id)) return notFound('That link was not found.');

	const access = await requireOrganizationPermission(event, 'files.share');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase
		.from('file_shares')
		.select(
			'id, client_id, issued_at, expires_at, revoked_at, first_viewed_at, last_viewed_at, view_count, client:clients(display_name), items:file_share_items(file_id, shared_name, position, file:files(id, display_name, mime_type, kind, size_bytes, thumbnail_object_key, processing_state, trashed_at))'
		)
		.eq('id', event.params.id)
		.maybeSingle();
	if (error) {
		console.error('Could not read a file share.', error);
		return databaseError();
	}
	if (!data) return notFound('That link was not found.');

	const { client, items, ...share } = data;
	return json(
		{
			share: {
				...share,
				client_name: embeddedOne(client)?.display_name ?? null,
				files: [...items]
					.sort((a, b) => a.position - b.position)
					.map((item) => ({ ...item, file: embeddedOne(item.file) }))
					.map((item) => ({
						file_id: item.file_id,
						shared_name: item.shared_name,
						// Null when this member's own file policies do not reach it; the frozen name still shows.
						file: item.file
							? {
									id: item.file.id,
									display_name: item.file.display_name,
									mime_type: item.file.mime_type,
									kind: item.file.kind,
									size_bytes: item.file.size_bytes,
									has_thumbnail: item.file.thumbnail_object_key !== null,
									processing_state: item.file.processing_state,
									trashed_at: item.file.trashed_at
								}
							: null
					}))
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
