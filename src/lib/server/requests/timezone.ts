import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Calendar statuses only make sense in the contractor's own timezone, so every request read needs this
// value. It is one row per organization and it almost never changes, so it is held in process for a few
// minutes rather than fetched again for every user on every page. Tenant-global, never per user.
//
// The same row also says which currency and locale the organization writes money in, so the Pipeline
// takes it from here rather than fetching the row a second time under a different name.
const CACHE_TTL_MS = 5 * 60 * 1000;

export type OrganizationFormatting = {
	timezone: string;
	currency_code: string;
	locale: string;
};

const FALLBACK: OrganizationFormatting = {
	timezone: 'UTC',
	currency_code: 'USD',
	locale: 'en-US'
};

const cache = new Map<string, { formatting: OrganizationFormatting; expiresAt: number }>();

export function forgetOrganizationTimezone(organizationId: string) {
	cache.delete(organizationId);
}

// Two different answers that must not be confused. An organization with no settings row yet genuinely
// has the defaults, and that answer is worth keeping for a few minutes. A database that could not be
// reached is not an answer at all: it is never cached, or every request for the next five minutes would
// be told the wrong currency and the wrong calendar day by a failure nobody saw.
export type FormattingLookup =
	{ ok: true; formatting: OrganizationFormatting } | { ok: false; formatting: null };

// Read with the server's own client, never the caller's. Every member needs these three presentation values
// to see their own work correctly, but organization_settings' row is readable only with
// settings.business.view -- a member denied Settings got no row back, which read as "brand new
// organization", and that UTC/USD answer was then cached for the whole team. Callers pass the organization
// from their verified membership (`auth.organization.id`), never a client-supplied id.
export async function organizationFormatting(organizationId: string): Promise<FormattingLookup> {
	const cached = cache.get(organizationId);
	if (cached && cached.expiresAt > Date.now()) return { ok: true, formatting: cached.formatting };

	const { data, error } = await getOwnerSupabaseClient()
		.from('organization_settings')
		.select('timezone, currency_code, locale')
		.eq('organization_id', organizationId)
		.maybeSingle();

	if (error) {
		console.error('Could not read organization settings.', error);
		return { ok: false, formatting: null };
	}

	// No row is a real answer: a brand new organization has not saved its settings yet.
	const formatting: OrganizationFormatting = {
		timezone: data?.timezone ?? FALLBACK.timezone,
		currency_code: data?.currency_code ?? FALLBACK.currency_code,
		locale: data?.locale ?? FALLBACK.locale
	};
	cache.set(organizationId, { formatting, expiresAt: Date.now() + CACHE_TTL_MS });
	return { ok: true, formatting };
}

// Requests have read this leniently since they were built: a lookup that fails falls back to UTC for
// that one request rather than failing the page. The failure is still never cached.
export async function organizationTimezone(organizationId: string) {
	const lookup = await organizationFormatting(organizationId);
	return lookup.ok ? lookup.formatting.timezone : FALLBACK.timezone;
}
