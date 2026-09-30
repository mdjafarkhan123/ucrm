import type { LayoutServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { organizationLogoUrl } from '$lib/server/settings/logo';
import type { AccountStanding } from '$lib/account/standing';

// The sidebar shows the business's own identity, not the product's, so it needs the saved logo alongside
// the organization the rest of the shell already loads. One extra column on a row this layout already
// reads — not a second query.
export const load: LayoutServerLoad = async (event) => {
	const user = await requireContractor(event);
	// Standing is asked alongside the context, not after it: a paused organization is hidden from its members,
	// so it gives no context, and the paused screen still has to know whose account it is.
	const [context, standingResult] = await Promise.all([
		getOrganizationContext(event, user),
		event.locals.supabase.rpc('contractor_account_standing')
	]);
	if (standingResult.error) console.error('Could not read account standing.', standingResult.error);
	const standing = (standingResult.data ?? null) as AccountStanding | null;
	if (!context) return { user, organization: null, logoUrl: null, standing };

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
		},
		standing
	};
};
