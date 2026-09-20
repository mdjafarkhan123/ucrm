import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { MarketingBusinessIdentity } from '$lib/server/marketing/render-email';

// The footer identity every rendered campaign email carries. Takes the organization name the caller's own
// permission check already resolved (src/lib/server/auth/organization.ts) instead of querying it again, and
// reads the same organization_settings address columns readiness.ts already checks for presence.
export async function getMarketingBusinessIdentity(
	organizationId: string,
	organizationName: string
): Promise<MarketingBusinessIdentity> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('organization_settings')
		.select('address_line1, address_line2, city, region, postal_code, country_code')
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;

	return {
		name: organizationName,
		addressLine1: data?.address_line1 ?? '',
		addressLine2: data?.address_line2 ?? null,
		city: data?.city ?? '',
		region: data?.region ?? null,
		postalCode: data?.postal_code ?? null,
		countryCode: data?.country_code ?? ''
	};
}
