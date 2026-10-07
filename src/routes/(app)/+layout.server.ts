import type { LayoutServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { organizationLogoUrl } from '$lib/server/settings/logo';
import type { AccountStanding } from '$lib/account/standing';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { contractorNavigation } from '$lib/server/access/navigation';
import { fallbackContractorNavigation, type ContractorNavigation } from '$lib/account/navigation';

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
	if (!context) {
		// The paused screen keeps Chat with Uplift (D5c), except for a closed business, which support no
		// longer serves; the database says which.
		let supportOpen = false;
		if (standing?.state === 'paused') {
			const { data, error } = await event.locals.supabase.rpc('support_member_context');
			if (error) console.error('Could not check support for a paused account.', error);
			supportOpen = Boolean(data);
		}
		return { user, organization: null, logoUrl: null, standing, supportOpen };
	}

	// The menu is drawn from the package and the member's permissions, resolved once here, so it is
	// complete on the first paint instead of each item asking the server after the page has loaded.
	const [settingsResult, profileResult, navigation] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select('logo_object_key, branding_revision')
			.eq('organization_id', context.organization.id)
			.maybeSingle(),
		event.locals.supabase.from('profiles').select('full_name').eq('id', user.id).maybeSingle(),
		resolveOrganizationAccess(event.locals.supabase, context.organization.id, user.id).then(
			(access): ContractorNavigation => contractorNavigation(access),
			(error): ContractorNavigation => {
				console.error('Could not resolve the menu access.', error);
				return fallbackContractorNavigation;
			}
		)
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
		navigation,
		standing,
		supportOpen: true
	};
};
