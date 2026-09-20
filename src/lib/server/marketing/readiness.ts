import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	buildMarketingReadiness,
	type MarketingReadiness,
	type MarketingReadinessFacts
} from '$lib/marketing/readiness';

// Answers "can this organization send Marketing email?" from the records that already own each fact. Every
// read is one small, indexed, single-organization lookup that stops at the first match, so the cost does not
// grow with the number of customers. It runs with the service key because the pause table is service-only;
// the caller has already proved the member may see Marketing, and every query is fixed to that organization.
export async function loadMarketingReadiness(organizationId: string): Promise<MarketingReadiness> {
	const owner = getOwnerSupabaseClient();

	const [domains, settings, pauses, allowance, consent] = await Promise.all([
		// A domain a sender can actually use: the same conditions the email worker checks before it sends.
		owner
			.from('communication_email_domains')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('purpose', 'sending')
			.eq('lifecycle_state', 'verified')
			.eq('provider_verified', true)
			.eq('provider_authenticated', true)
			.eq('ownership_status', 'passing')
			.eq('dkim_status', 'passing'),
		owner
			.from('organization_settings')
			.select('address_line1, city, country_code')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		// Any live pause holds optional email such as Marketing, whether it covers this organization or the
		// whole platform.
		owner
			.from('communication_email_sending_pauses')
			.select('id')
			.is('released_at', null)
			.or(`scope.eq.platform,organization_id.eq.${organizationId}`)
			.limit(1),
		owner.rpc('effective_marketing_email_limit', { target_organization_id: organizationId }),
		owner
			.from('client_marketing_consent_state')
			.select('client_contact_method_id')
			.eq('organization_id', organizationId)
			.eq('state', 'opted_in')
			.limit(1)
	]);

	for (const result of [domains, settings, pauses, allowance, consent]) {
		if (result.error) throw result.error;
	}

	const domainIds = (domains.data ?? []).map((domain) => domain.id);
	let hasEnabledSender = false;
	if (domainIds.length > 0) {
		const senders = await owner
			.from('communication_email_senders')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('lifecycle_state', 'enabled')
			.in('domain_id', domainIds)
			.limit(1);
		if (senders.error) throw senders.error;
		hasEnabledSender = (senders.data ?? []).length > 0;
	}

	const address = settings.data;
	const limitState = allowance.data?.[0]?.state;

	const facts: MarketingReadinessFacts = {
		hasVerifiedSendingDomain: domainIds.length > 0,
		hasEnabledSender,
		hasBusinessAddress: Boolean(address?.address_line1 && address.city && address.country_code),
		sendingPaused: (pauses.data ?? []).length > 0,
		// An unreadable or missing answer is treated as not configured: the safe side is to block.
		allowanceState:
			limitState === 'numeric' || limitState === 'unlimited' ? limitState : 'not_included',
		hasConsentedCustomer: (consent.data ?? []).length > 0
	};

	return buildMarketingReadiness(facts);
}
