import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { renameKeepingExtension } from '$lib/server/files/upload-policy';
import { fileUpdateSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// How many usage rows the details panel opens with. "Show more" asks for the next page rather than
// rendering an unbounded relationship list, which is what the contract requires.
const USAGE_PAGE_SIZE = 10;

// Deliberately not gated on files.view. A member without the library permission may still open a file they
// reached through a job or a quote they can see, and the files policy is what decides whether this row
// comes back at all -- the same rule for everyone, enforced by the database rather than repeated here.
export const GET: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	const auth = await getOrganizationContext(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	const cursor = event.url.searchParams.get('usage_cursor');
	const separator = cursor?.lastIndexOf('|') ?? -1;
	const usageCursor =
		cursor && separator > 0
			? { createdAt: cursor.slice(0, separator), id: cursor.slice(separator + 1) }
			: null;

	const [fileResult, usageResult, access] = await Promise.all([
		event.locals.supabase
			.from('files')
			.select(
				'id, display_name, mime_type, kind, size_bytes, thumbnail_object_key, folder_id, origin_type, origin_id, processing_state, uploaded_by, created_at, trashed_at'
			)
			.eq('id', fileId)
			.maybeSingle(),
		event.locals.supabase.rpc('file_usage', {
			target_organization_id: auth.organization.id,
			target_file_id: fileId,
			target_limit: USAGE_PAGE_SIZE + 1,
			cursor_created_at: usageCursor?.createdAt ?? undefined,
			cursor_id: usageCursor?.id ?? undefined
		}),
		resolveOrganizationAccess(event.locals.supabase, auth.organization.id, auth.user.id)
	]);

	if (fileResult.error) {
		console.error('Could not read a file.', fileResult.error);
		return databaseError();
	}
	// No row means the policies did not let this reader have it. "Not found" is the right answer either
	// way: a file they may not see must not be distinguishable from one that does not exist.
	if (!fileResult.data) return json({ error: 'That file was not found.' }, { status: 404 });
	if (usageResult.error) {
		console.error('Could not read a file usage list.', usageResult.error);
		return databaseError();
	}

	const usageRows = usageResult.data ?? [];
	const hasMoreUsage = usageRows.length > USAGE_PAGE_SIZE;
	const usage = hasMoreUsage ? usageRows.slice(0, USAGE_PAGE_SIZE) : usageRows;
	const lastUsage = usage.at(-1);

	const [folderResult, uploaderResult] = await Promise.all([
		fileResult.data.folder_id
			? event.locals.supabase
					.from('file_folders')
					.select('id, name')
					.eq('id', fileResult.data.folder_id)
					.maybeSingle()
			: Promise.resolve({ data: null }),
		fileResult.data.uploaded_by
			? event.locals.supabase
					.from('profiles')
					.select('full_name')
					.eq('id', fileResult.data.uploaded_by)
					.maybeSingle()
			: Promise.resolve({ data: null })
	]);

	const { thumbnail_object_key, ...file } = fileResult.data;

	return json(
		{
			file: {
				...file,
				has_thumbnail: thumbnail_object_key !== null,
				folder_name: folderResult.data?.name ?? null,
				uploaded_by_name: uploaderResult.data?.full_name ?? null
			},
			usage,
			usage_next_cursor:
				hasMoreUsage && lastUsage ? `${lastUsage.created_at}|${lastUsage.id}` : null,
			can_manage: hasPermission(access, 'files.manage'),
			can_trash: hasPermission(access, 'files.trash')
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Rename, move, or both. Folders are a display grouping, so neither of these touches a link: a file moved
// into "Boiler jobs" is still attached to exactly the jobs and quotes it was attached to before.
export const PATCH: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;
	const organizationId = access.auth.organization.id;
	const owner = getOwnerSupabaseClient();

	let file: unknown = null;

	if (parsed.data.display_name !== undefined) {
		// Read under the caller's own policies first: the new name has to keep the old one's extension, and
		// a file this member cannot see must answer "not found" rather than quietly refusing later.
		const current = await event.locals.supabase
			.from('files')
			.select('display_name')
			.eq('id', fileId)
			.maybeSingle();
		if (current.error) {
			console.error('Could not read a file before renaming it.', current.error);
			return databaseError();
		}
		if (!current.data) return json({ error: 'That file was not found.' }, { status: 404 });

		const { data, error } = await owner.rpc('rename_file', {
			target_organization_id: organizationId,
			target_file_id: fileId,
			target_actor_id: access.auth.user.id,
			target_display_name: renameKeepingExtension(
				current.data.display_name,
				parsed.data.display_name
			)
		});
		if (error) {
			if (error.code === 'P0002')
				return json({ error: 'That file was not found.' }, { status: 404 });
			console.error('Could not rename a file.', error);
			return databaseError();
		}
		file = data;
	}

	if (parsed.data.folder_id !== undefined) {
		const { data, error } = await owner.rpc('move_file_to_folder', {
			target_organization_id: organizationId,
			target_file_id: fileId,
			target_actor_id: access.auth.user.id,
			// "Out of every folder" is null, and the function already defaults this argument to null;
			// `undefined` is how the generated client omits an argument rather than sending JSON null.
			target_folder_id: parsed.data.folder_id ?? undefined
		});
		if (error) {
			if (error.code === 'P0002')
				return json({ error: 'That file or folder was not found.' }, { status: 404 });
			console.error('Could not move a file.', error);
			return databaseError();
		}
		file = data;
	}

	return json({ file });
};
