import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import {
	resolveOrganizationAccess,
	type EffectiveOrganizationAccess
} from '$lib/server/access/effective';
import { canDescribeFile } from '$lib/server/files/describe-access';
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
				'id, display_name, caption, mime_type, kind, size_bytes, thumbnail_object_key, folder_id, origin_type, origin_id, processing_state, uploaded_by, created_at, trashed_at'
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

	const [folderResult, uploaderResult, labelsResult, canDescribe] = await Promise.all([
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
			: Promise.resolve({ data: null }),
		event.locals.supabase.from('file_label_assignments').select('label_id').eq('file_id', fileId),
		fileResult.data.kind === 'image' && fileResult.data.trashed_at === null
			? canDescribeFile(event.locals.supabase, access, fileId)
			: Promise.resolve(false)
	]);
	if (labelsResult.error) {
		console.error("Could not read a file's labels.", labelsResult.error);
		return databaseError();
	}
	const labelIds = (labelsResult.data ?? []).map((row) => row.label_id);
	const labelNames = labelIds.length
		? await event.locals.supabase.from('file_labels').select('id, name').in('id', labelIds)
		: { data: [], error: null };
	if (labelNames.error) {
		console.error("Could not read a file's label names.", labelNames.error);
		return databaseError();
	}
	const labels = (labelNames.data ?? []).sort((a, b) =>
		a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
	);

	const { thumbnail_object_key, ...file } = fileResult.data;

	return json(
		{
			file: {
				...file,
				has_thumbnail: thumbnail_object_key !== null,
				folder_name: folderResult.data?.name ?? null,
				uploaded_by_name: uploaderResult.data?.full_name ?? null,
				labels
			},
			usage,
			usage_next_cursor:
				hasMoreUsage && lastUsage ? `${lastUsage.created_at}|${lastUsage.id}` : null,
			can_manage: hasPermission(access, 'files.manage'),
			can_trash: hasPermission(access, 'files.trash'),
			can_describe: canDescribe
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Rename, move, caption, label -- any combination. Folders are a display grouping, so none of these touches a
// link: a file moved into "Boiler jobs" is still attached to exactly the jobs and quotes it was attached to
// before. Renaming and moving need files.manage; captioning and labelling a photo need only canDescribeFile.
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

	const managing = parsed.data.display_name !== undefined || parsed.data.folder_id !== undefined;
	const describing = parsed.data.caption !== undefined || parsed.data.label_ids !== undefined;

	let access: { auth: OrganizationContext; access: EffectiveOrganizationAccess };
	if (managing) {
		const check = await requireOrganizationPermission(event, 'files.manage');
		if ('response' in check) return check.response;
		access = check;
	} else {
		const auth = await getOrganizationContext(event);
		if (!auth)
			return json(
				{ error: 'Authentication or organization membership required.' },
				{ status: 401 }
			);
		access = {
			auth,
			access: await resolveOrganizationAccess(
				event.locals.supabase,
				auth.organization.id,
				auth.user.id
			)
		};
	}
	const organizationId = access.auth.organization.id;
	const owner = getOwnerSupabaseClient();

	if (describing && !(await canDescribeFile(event.locals.supabase, access.access, fileId))) {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}

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

	if (describing) {
		const { data, error } = await owner.rpc('describe_file', {
			target_organization_id: organizationId,
			target_file_id: fileId,
			target_actor_id: access.auth.user.id,
			set_caption: parsed.data.caption !== undefined,
			// Null and empty both clear the caption; the database turns an empty box into null.
			target_caption: parsed.data.caption ?? '',
			// Absent means "leave the labels alone", which the function reads as a null list.
			target_label_ids: (parsed.data.label_ids ?? null) as string[]
		});
		if (error) {
			if (error.code === 'P0002')
				return json({ error: 'That file was not found.' }, { status: 404 });
			if (error.code === 'P0404')
				return validationError({
					label_ids: 'One of those labels was just removed. Reopen the list and try again.'
				});
			if (error.code === '23514')
				return validationError({ caption: 'Only photos take a caption or labels.' });
			console.error('Could not describe a file.', error);
			return databaseError();
		}
		file = data;
	}

	return json({ file });
};
