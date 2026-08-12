import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	memberPermissionOverrideSchema,
	permissionKeySchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const PATCH: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	const parsedPermissionKey = permissionKeySchema.safeParse(event.params.permissionKey);
	if (!parsedUserId.success || !parsedPermissionKey.success) {
		return json(
			{
				error: 'The employee or permission identifier is invalid.',
				field_errors: {
					...(parsedUserId.success ? {} : zodAccessFieldErrors(parsedUserId.error)),
					...(parsedPermissionKey.success ? {} : { permission_key: 'Use a valid permission key.' })
				}
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = memberPermissionOverrideSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the requested permission override.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const { auth } = required.context;
	const supabase = event.locals.supabase;
	const { data: member, error: memberError } = await supabase
		.from('organization_members')
		.select('user_id, role')
		.eq('organization_id', auth.organization.id)
		.eq('user_id', parsedUserId.data)
		.maybeSingle();
	if (memberError) {
		console.error('Could not load employee before permission change.', memberError);
		return json({ error: 'The permission override could not be saved.' }, { status: 500 });
	}
	if (!member) return json({ error: 'Employee was not found.' }, { status: 404 });

	const { data: permission, error: permissionError } = await supabase
		.from('permissions')
		.select('key')
		.eq('key', parsedPermissionKey.data)
		.maybeSingle();
	if (permissionError) {
		console.error('Could not verify permission key.', permissionError);
		return json({ error: 'The permission override could not be saved.' }, { status: 500 });
	}
	if (!permission) return json({ error: 'Permission was not found.' }, { status: 404 });

	const isPrivilegedRole = member.role === 'owner' || member.role === 'admin';
	if (
		parsedPermissionKey.data === 'team.manage' &&
		parsed.data.override_state === 'deny' &&
		(parsedUserId.data === auth.user.id || isPrivilegedRole)
	) {
		return json(
			{ error: 'An owner or admin must retain team management access.' },
			{ status: 409 }
		);
	}

	if (parsed.data.override_state === 'inherit') {
		const { error: deleteError } = await supabase
			.from('organization_member_permission_overrides')
			.delete()
			.eq('organization_id', auth.organization.id)
			.eq('user_id', parsedUserId.data)
			.eq('permission_key', parsedPermissionKey.data);
		if (deleteError) {
			console.error('Could not remove employee permission override.', deleteError);
			return json({ error: 'The permission override could not be saved.' }, { status: 500 });
		}
		return json({ override: null, override_state: 'inherit' });
	}

	const { data: override, error: upsertError } = await supabase
		.from('organization_member_permission_overrides')
		.upsert(
			{
				organization_id: auth.organization.id,
				user_id: parsedUserId.data,
				permission_key: parsedPermissionKey.data,
				override_state: parsed.data.override_state
			},
			{ onConflict: 'organization_id,user_id,permission_key' }
		)
		.select('user_id, permission_key, override_state, created_at, updated_at')
		.single();
	if (upsertError) {
		console.error('Could not save employee permission override.', upsertError);
		return json({ error: 'The permission override could not be saved.' }, { status: 500 });
	}

	return json({ override });
};
