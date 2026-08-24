import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { businessHoursIsSet, businessProfileReadiness } from '$lib/server/settings/readiness';

// What the Settings home needs and nothing more: who is signed in, whether they may change business
// settings, and one honest status per destination. No decorative badges — a card says something only
// when there is a real gap behind it.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const [settingsResult, profileResult, currencyLockResult] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select('timezone_confirmed_at, currency_confirmed_at, hours_mode')
			.eq('organization_id', check.auth.organization.id)
			.maybeSingle(),
		event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', check.auth.user.id)
			.maybeSingle(),
		event.locals.supabase.rpc('organization_currency_is_locked', {
			target_organization_id: check.auth.organization.id
		})
	]);

	if (settingsResult.error || currencyLockResult.error) return databaseError();
	if (!settingsResult.data) return notFound('These business settings could not be found.');

	const settings = settingsResult.data;

	return json(
		{
			member: {
				name: profileResult.data?.full_name ?? null,
				email: check.auth.user.email ?? null,
				role: check.auth.organization.role
			},
			organization: { name: check.auth.organization.name },
			permissions: {
				business_edit: hasPermission(check.access, 'settings.business.edit'),
				team_manage: hasPermission(check.access, 'team.manage'),
				communications_manage: hasPermission(check.access, 'conversations.manage_connections'),
				taxes_manage: hasPermission(check.access, 'settings.taxes.manage'),
				price_book_manage: hasPermission(check.access, 'settings.price_book.manage'),
				quotes_manage: hasPermission(check.access, 'settings.quotes.manage')
			},
			readiness: {
				business_profile: businessProfileReadiness({
					name: check.auth.organization.name,
					timezone_confirmed_at: settings.timezone_confirmed_at,
					currency_confirmed_at: settings.currency_confirmed_at,
					currency_locked: currencyLockResult.data === true
				}),
				business_hours_set: businessHoursIsSet(settings.hours_mode)
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
