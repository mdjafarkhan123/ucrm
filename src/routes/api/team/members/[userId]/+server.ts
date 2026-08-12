import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	memberRoleChangeSchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const PATCH: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json(
			{
				error: 'The employee identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedUserId.error)
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

	const parsed = memberRoleChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the requested role.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const { auth } = required.context;
	const supabase = event.locals.supabase;
	const { data: member, error: memberError } = await supabase
		.from('organization_members')
		.select('user_id, role, created_at')
		.eq('organization_id', auth.organization.id)
		.eq('user_id', parsedUserId.data)
		.maybeSingle();
	if (memberError) {
		console.error('Could not load employee before role change.', memberError);
		return json({ error: 'The employee role could not be changed.' }, { status: 500 });
	}
	if (!member) return json({ error: 'Employee was not found.' }, { status: 404 });

	const isPrivilegedRole = (role: string) => role === 'owner' || role === 'admin';
	if (parsedUserId.data === auth.user.id && !isPrivilegedRole(parsed.data.role)) {
		return json(
			{ error: 'You cannot remove your own organization administrator access.' },
			{ status: 409 }
		);
	}

	if (isPrivilegedRole(member.role) && !isPrivilegedRole(parsed.data.role)) {
		const { count, error: countError } = await supabase
			.from('organization_members')
			.select('user_id', { count: 'exact', head: true })
			.eq('organization_id', auth.organization.id)
			.in('role', ['owner', 'admin']);
		if (countError) {
			console.error('Could not verify administrator coverage.', countError);
			return json({ error: 'The employee role could not be changed.' }, { status: 500 });
		}
		if ((count ?? 0) <= 1) {
			return json(
				{ error: 'The organization must retain at least one owner or admin.' },
				{ status: 409 }
			);
		}
	}

	const { data: updatedMember, error: updateError } = await supabase
		.from('organization_members')
		.update({ role: parsed.data.role })
		.eq('organization_id', auth.organization.id)
		.eq('user_id', parsedUserId.data)
		.select('user_id, role, created_at')
		.single();
	if (updateError) {
		if (updateError.code === '23514') {
			return json(
				{ error: 'The organization must retain at least one owner or admin.' },
				{ status: 409 }
			);
		}
		console.error('Could not change employee role.', updateError);
		return json({ error: 'The employee role could not be changed.' }, { status: 500 });
	}

	return json({ member: updatedMember });
};
