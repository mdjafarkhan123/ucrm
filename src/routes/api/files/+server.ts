import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission, hasPermission } from '$lib/server/access/permission';
import { requireLinkedEntityAccess, type LinkedEntityType } from '$lib/server/access/collaboration';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// The smart views in the left rail, plus the folder view. "Videos" is deliberately absent: video is not on
// the upload allowlist until Part 8 measures it, so it could only ever be an empty list that implies a missing
// feature. "Shared with customers" lists shares rather than files, so it has its own route
// (/api/files/shares); this one only says whether the rail should offer it (`has_shares`).
// `label` is one photo label from the rail, named by `label_id`, the way `folder` names its folder.
// `on_record` is the picker's first section rather than a rail view: the Files already on the record the
// picker was opened from. It needs the record named, so it is the one view that reads entity_type/entity_id.
const VIEWS = [
	'all',
	'recent',
	'photos',
	'documents',
	'not_attached',
	'trash',
	'folder',
	'label',
	'on_record'
] as const;
type FileView = (typeof VIEWS)[number];

const ENTITY_TYPES = [
	'client',
	'property',
	'request',
	'quote',
	'job_expense',
	'job',
	'visit',
	'invoice',
	'organization'
] as const;

const PAGE_SIZE_DEFAULT = 40;
const PAGE_SIZE_MAX = 100;

function readView(raw: string | null): FileView {
	return (VIEWS as readonly string[]).includes(raw ?? '') ? (raw as FileView) : 'all';
}

// Cursor format: "<created_at>|<id>". Both halves are needed, because created_at alone is not unique and a
// tie at a page boundary would silently drop or repeat a file.
function readCursor(raw: string | null) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const createdAt = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (!createdAt || !id) return null;
	return { createdAt, id };
}

export const GET: RequestHandler = async (event) => {
	const params = event.url.searchParams;
	const view = readView(params.get('view'));
	const folderId = view === 'folder' ? params.get('folder_id') : null;
	if (view === 'folder' && !folderId) return json({ files: [], next_cursor: null });
	const labelId = view === 'label' ? params.get('label_id') : null;
	if (view === 'label' && !labelId) return json({ files: [], next_cursor: null });

	// The record the picker was opened from. A view of `on_record` without one would otherwise read as "no
	// record named, so show everything", which is the opposite of what the section means.
	const entityTypeParam = params.get('entity_type');
	const entityType = (ENTITY_TYPES as readonly string[]).includes(entityTypeParam ?? '')
		? entityTypeParam
		: null;
	const entityId = params.get('entity_id');
	if (view === 'on_record' && (!entityType || !entityId))
		return json({ files: [], next_cursor: null });

	// Browsing the library is its own permission. A member without it still reaches a file through a
	// record it may view — that is `on_record`'s whole point, so it is gated on the record itself (the
	// same gate its notes and other attachments already use) rather than on `files.view`. Every other view
	// really is "browse the whole library", so it keeps the library gate.
	let organizationId: string;
	let userId: string;
	if (view === 'on_record' && entityType && entityId) {
		const recordAccess = await requireLinkedEntityAccess(
			event,
			entityType as LinkedEntityType,
			'view'
		);
		if ('response' in recordAccess) return recordAccess.response;
		organizationId = recordAccess.auth.organization.id;
		userId = recordAccess.auth.user.id;
	} else {
		const libraryAccess = await requireOrganizationPermission(event, 'files.view');
		if ('response' in libraryAccess) return libraryAccess.response;
		organizationId = libraryAccess.auth.organization.id;
		userId = libraryAccess.auth.user.id;
	}
	const access = await resolveOrganizationAccess(event.locals.supabase, organizationId, userId);

	// The picker asks for this: a file that is still being checked, failed a check, or was quarantined
	// cannot be attached to anything, so offering it would be offering a button that must then refuse.
	const attachableOnly = params.get('attachable') === '1';

	const search = params.get('search')?.trim() || null;
	const limit = Math.min(
		PAGE_SIZE_MAX,
		Math.max(
			1,
			Number.parseInt(params.get('limit') ?? String(PAGE_SIZE_DEFAULT), 10) || PAGE_SIZE_DEFAULT
		)
	);
	const cursor = readCursor(params.get('cursor'));

	// One page and its usage counts in a single statement, under the caller's own policies -- see the
	// migration for why this is a function rather than a PostgREST query.
	const { data, error } = await event.locals.supabase.rpc('list_files', {
		target_organization_id: organizationId,
		// A label is only ever on a photo, so the label view is the photos view narrowed to it.
		target_view: view === 'folder' ? 'all' : view === 'label' ? 'photos' : view,
		target_folder_id: folderId ?? undefined,
		target_search: search ?? undefined,
		// One more than the page, so "is there another page" is answered without a second count query.
		target_limit: limit + 1,
		cursor_created_at: cursor?.createdAt ?? undefined,
		cursor_id: cursor?.id ?? undefined,
		target_entity_type: entityType ?? undefined,
		target_entity_id: entityId ?? undefined,
		only_attachable: attachableOnly,
		target_label_id: labelId ?? undefined
	});
	if (error) {
		console.error('Could not list files.', error);
		return databaseError();
	}

	// The rail offers "Shared with customers" only once there is a share to list. Asked on the first page
	// alone -- one indexed row, under the caller's own policies -- and only of someone who may share.
	const canShare = hasPermission(access, 'files.share');
	let hasShares = false;
	if (canShare && !cursor) {
		const shareProbe = await event.locals.supabase.from('file_shares').select('id').limit(1);
		if (shareProbe.error) console.error('Could not check for file shares.', shareProbe.error);
		hasShares = (shareProbe.data ?? []).length > 0;
	}

	const rows = data ?? [];
	const hasMore = rows.length > limit;
	const files = hasMore ? rows.slice(0, limit) : rows;
	const last = files.at(-1);

	return json(
		{
			files,
			next_cursor: hasMore && last ? `${last.created_at}|${last.id}` : null,
			// What this member may do with what they are looking at, resolved once here rather than guessed
			// in the browser. Every write re-checks it server-side; this only decides which buttons show.
			can_manage: hasPermission(access, 'files.manage'),
			can_trash: hasPermission(access, 'files.trash'),
			can_share: canShare,
			has_shares: hasShares
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
