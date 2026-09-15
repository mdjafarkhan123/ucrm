import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { businessProfileReadiness } from '$lib/server/settings/readiness';
import { computeOnboardingChecklist } from '$lib/server/onboarding/checklist';

// Owner/admin only: the getting-started nudge is for whoever is setting the organization up, not every
// role that happens to load the dashboard.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	const [
		settingsResult,
		currencyLockResult,
		catalogResult,
		clientResult,
		invitationResult,
		memberResult
	] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select('timezone_confirmed_at, currency_confirmed_at')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		event.locals.supabase.rpc('organization_currency_is_locked', {
			target_organization_id: organizationId
		}),
		event.locals.supabase
			.from('catalog_items')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.is('archived_at', null),
		event.locals.supabase
			.from('clients')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.is('deleted_at', null),
		event.locals.supabase
			.from('organization_member_invitations')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.in('state', ['invited', 'accepting', 'accepted']),
		event.locals.supabase
			.from('organization_members')
			.select('user_id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('status', 'active')
	]);

	if (
		settingsResult.error ||
		currencyLockResult.error ||
		catalogResult.error ||
		clientResult.error ||
		invitationResult.error ||
		memberResult.error
	)
		return databaseError();
	if (!settingsResult.data) return databaseError();

	const { items, allComplete } = computeOnboardingChecklist({
		businessProfileComplete: businessProfileReadiness({
			name: check.auth.organization.name,
			timezone_confirmed_at: settingsResult.data.timezone_confirmed_at,
			currency_confirmed_at: settingsResult.data.currency_confirmed_at,
			currency_locked: currencyLockResult.data === true
		}).complete,
		hasCatalogItem: (catalogResult.count ?? 0) > 0,
		hasClient: (clientResult.count ?? 0) > 0,
		teamInvited: (invitationResult.count ?? 0) > 0 || (memberResult.count ?? 0) > 1
	});

	return json({ items, all_complete: allComplete }, { headers: PRIVATE_READ_HEADERS });
};
