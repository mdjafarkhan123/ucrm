import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { organizationLogoUrl } from '$lib/server/settings/logo';
import { businessProfileReadiness, businessHoursIsSet } from '$lib/server/settings/readiness';

// One read for all three settings pages. They edit different parts of the same record and each carries
// its own revision, so whichever page the person opens starts from the same truth and conflicts only
// with somebody editing that same section.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	// Four small reads that do not depend on each other. Settings is a rare page, but there is no reason
	// to pay for them one after another.
	const [settingsResult, hoursResult, profileResult, currencyLockResult] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select(
				'trade, phone, website, description, address_line1, address_line2, city, region, postal_code, country_code, address_is_public, timezone, locale, currency_code, timezone_confirmed_at, currency_confirmed_at, brand_color, logo_object_key, hours_mode, profile_revision, branding_revision, hours_revision, profile_updated_at, branding_updated_at, hours_updated_at, profile_updated_by, branding_updated_by, hours_updated_by'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		event.locals.supabase
			.from('organization_business_hours')
			.select('weekday, period_index, is_open, is_open_24h, opens_at, closes_at')
			.eq('organization_id', organizationId)
			.order('weekday')
			.order('period_index'),
		event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', check.auth.user.id)
			.maybeSingle(),
		event.locals.supabase.rpc('organization_currency_is_locked', {
			target_organization_id: organizationId
		})
	]);

	if (settingsResult.error || hoursResult.error || currencyLockResult.error) return databaseError();
	if (!settingsResult.data) return notFound('These business settings could not be found.');

	const settings = settingsResult.data;

	// Whoever last touched each section, by name. One extra read only when somebody has actually saved.
	const editorIds = [
		settings.profile_updated_by,
		settings.branding_updated_by,
		settings.hours_updated_by
	].filter((id): id is string => typeof id === 'string');

	const editorNames = new Map<string, string | null>();
	if (editorIds.length > 0) {
		const { data: editors } = await event.locals.supabase
			.from('profiles')
			.select('id, full_name')
			.in('id', [...new Set(editorIds)]);
		for (const editor of editors ?? []) editorNames.set(editor.id, editor.full_name);
	}

	const editor = (id: string | null, at: string | null) =>
		id ? { name: editorNames.get(id) ?? null, at } : null;

	const canEdit = hasPermission(check.access, 'settings.business.edit');

	return json(
		{
			member: {
				name: profileResult.data?.full_name ?? null,
				email: check.auth.user.email ?? null,
				role: check.auth.organization.role
			},
			permissions: { view: true, edit: canEdit },
			profile: {
				name: check.auth.organization.name,
				trade: settings.trade,
				phone: settings.phone,
				website: settings.website,
				description: settings.description,
				address_line1: settings.address_line1,
				address_line2: settings.address_line2,
				city: settings.city,
				region: settings.region,
				postal_code: settings.postal_code,
				country_code: settings.country_code,
				address_is_public: settings.address_is_public,
				timezone: settings.timezone,
				locale: settings.locale,
				currency_code: settings.currency_code,
				timezone_confirmed: settings.timezone_confirmed_at !== null,
				currency_confirmed: settings.currency_confirmed_at !== null,
				revision: settings.profile_revision,
				last_editor: editor(settings.profile_updated_by, settings.profile_updated_at)
			},
			branding: {
				brand_color: settings.brand_color,
				// The storage key never leaves the server. The page gets the URL that serves it, and only
				// when there is something to serve.
				logo_url: settings.logo_object_key ? organizationLogoUrl(settings.branding_revision) : null,
				revision: settings.branding_revision,
				last_editor: editor(settings.branding_updated_by, settings.branding_updated_at)
			},
			hours: {
				mode: settings.hours_mode,
				periods: hoursResult.data ?? [],
				revision: settings.hours_revision,
				last_editor: editor(settings.hours_updated_by, settings.hours_updated_at)
			},
			readiness: {
				profile: businessProfileReadiness({
					name: check.auth.organization.name,
					timezone_confirmed_at: settings.timezone_confirmed_at,
					currency_confirmed_at: settings.currency_confirmed_at,
					currency_locked: currencyLockResult.data === true
				}),
				hours_set: businessHoursIsSet(settings.hours_mode)
			},
			// Quote totals already carry a frozen currency code, so mixing currencies inside one
			// organization has no honest meaning once a customer has seen one. The page shows this as
			// locked rather than letting the save fail.
			currency_locked: currencyLockResult.data === true
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
