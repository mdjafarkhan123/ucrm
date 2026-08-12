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

	const { data, error } = await event.locals.supabase
		.from('organization_members')
		.select('organization_id, role, organizations(id, name)')
		.eq('user_id', resolvedUser.id)
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
