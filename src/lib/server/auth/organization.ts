import type { RequestEvent } from '@sveltejs/kit';

export type OrganizationContext = {
	user: NonNullable<Awaited<ReturnType<RequestEvent['locals']['getUser']>>>;
	organization: { id: string; name: string; role: string };
};

export async function getOrganizationContext(
	event: RequestEvent,
	user?: OrganizationContext['user']
) {
	const resolvedUser = user ?? (await event.locals.getUser());
	if (!resolvedUser) return null;

	// Only an active membership is an organization. Someone who was invited but has not finished
	// accepting, someone deactivated, and someone permanently removed all get no context at all, so every
	// route and page that asks this question stops them in the same place rather than each remembering to
	// check status for itself. The database says the same thing through the seven membership helpers;
	// this is the same rule at the door.
	// The FK must be named explicitly: communication_conversation_followers' composite FK to
	// organization_members plus its own FK to organizations reads as a second, many-to-many path between
	// the two tables, so the bare `organizations(...)` embed is ambiguous (PGRST201).
	const { data, error } = await event.locals.supabase
		.from('organization_members')
		.select(
			'organization_id, role, organizations!organization_members_organization_id_fkey(id, name)'
		)
		.eq('user_id', resolvedUser.id)
		.eq('status', 'active')
		.maybeSingle();

	if (error || !data || !data.organizations) return null;

	const organization = Array.isArray(data.organizations)
		? data.organizations[0]
		: data.organizations;
	if (!organization) return null;

	return {
		user: resolvedUser,
		organization: { id: organization.id, name: organization.name, role: data.role }
	};
}

export async function requireOrganization(
	event: RequestEvent
): Promise<OrganizationContext | null> {
	return getOrganizationContext(event);
}
