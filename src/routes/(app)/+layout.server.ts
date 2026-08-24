import type { LayoutServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { organizationLogoUrl } from '$lib/server/settings/logo';

// The sidebar shows the business's own identity, not the product's, so it needs the saved logo alongside
// the organization the rest of the shell already loads. One extra column on a row this layout already
// reads — not a second query.
export const load: LayoutServerLoad = async (event) => {
	const user = await requireContractor(event);
	const context = await getOrganizationContext(event, user);
	if (!context) return { user, organization: null, logoUrl: null };

	const [settingsResult, profileResult] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select('logo_object_key, branding_revision')
			.eq('organization_id', context.organization.id)
			.maybeSingle(),
		event.locals.supabase.from('profiles').select('full_name').eq('id', user.id).maybeSingle()
	]);
	const settings = settingsResult.data;

	return {
		...context,
		logoUrl: settings?.logo_object_key ? organizationLogoUrl(settings.branding_revision) : null,
		account: {
			name: profileResult.data?.full_name ?? null,
			email: user.email ?? null,
			role: context.organization.role
		}
	};
};
