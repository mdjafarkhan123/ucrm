import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	buildMarketingReadiness,
	type MarketingReadiness,
	type MarketingReadinessFacts
} from '$lib/marketing/readiness';
import type { MarketingWarmupProgress } from '$lib/marketing/warmup';

// Answers "can this organization send Marketing email?" from the records that already own each fact. Every
// read is one small, indexed, single-organization lookup that stops at the first match, so the cost does not
// grow with the number of customers. It runs with the service key because the pause table is service-only;
// the caller has already proved the member may see Marketing, and every query is fixed to that organization.
export async function loadMarketingReadiness(organizationId: string): Promise<MarketingReadiness> {
	const owner = getOwnerSupabaseClient();

	const [domains, senderDomains, settings, pauses, allowance, consent, warmup] = await Promise.all([
		// Marketing sends through its OWN Amazon SES identity on news.<root>, never through the operational
		// mail.<root> domain, so this must ask about purpose='marketing_sending'. spf_status is part of the test
		// because the custom MAIL FROM subdomain is what gives a bulk stream its SPF alignment -- an identity
		// without it is not honestly ready to send a campaign.
		owner
			.from('communication_email_domains')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('purpose', 'marketing_sending')
			.eq('lifecycle_state', 'verified')
			.eq('provider_verified', true)
			.eq('provider_authenticated', true)
			.eq('ownership_status', 'passing')
			.eq('dkim_status', 'passing')
			.eq('spf_status', 'passing'),
		// The contractor's operational sending domain, which is where their chosen sender identity (the
		// display name and address customers already recognise) lives. Marketing's own From address is derived
		// from it, so a contractor with no sender still has nothing to send as.
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
			.limit(1),
		// Earned warm-up progress for the Overview card: one organization, bounded by one step's sends.
		owner.rpc('get_marketing_warmup_progress', { p_organization_id: organizationId })
	]);

	for (const result of [domains, senderDomains, settings, pauses, allowance, consent]) {
		if (result.error) throw result.error;
	}

	const domainIds = (domains.data ?? []).map((domain) => domain.id);
	const senderDomainIds = (senderDomains.data ?? []).map((domain) => domain.id);
	let hasEnabledSender = false;
	if (senderDomainIds.length > 0) {
		const senders = await owner
			.from('communication_email_senders')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('lifecycle_state', 'enabled')
			.in('domain_id', senderDomainIds)
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

	// The progress card is informational, so a failed read hides it rather than failing readiness.
	if (warmup.error) console.error('Could not read Marketing warm-up progress.', warmup.error);

	return {
		...buildMarketingReadiness(facts),
		warmup: warmup.error ? null : (warmup.data as MarketingWarmupProgress)
	};
}
