import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Everything the campaign journey's Delivery step (blueprint §8 step 4) needs to display or offer as a call
// to action, gathered from the records that already own each fact -- same split as readiness.ts, which this
// reuses the eligible-sender query from. Sender and reply-destination are shown, not chosen, in this slice
// (Memory/campaigns/marketing-growth/NOW.md): a contractor with more than one eligible sender is out of scope
// until M4 needs a real send-time choice, so this always resolves to the organization's default sender.

export type MarketingDeliverySender = {
	id: string;
	email_address: string;
	display_name: string;
};

export type MarketingDeliveryForm = {
	id: string;
	name: string;
	outcome: string;
	public_slug: string;
};

export type MarketingDeliveryOptions = {
	sender: MarketingDeliverySender | null;
	business_phone: string | null;
	business_website: string | null;
	// Only forms a customer could actually land on right now: enabled, published, not archived.
	forms: MarketingDeliveryForm[];
	allowance: { state: string; value: number | null; is_unlimited: boolean };
};

export async function loadMarketingDeliveryOptions(
	organizationId: string
): Promise<MarketingDeliveryOptions> {
	const owner = getOwnerSupabaseClient();

	const [domains, marketingDomain, settings, forms, allowance] = await Promise.all([
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
		// The verified news.<root> domain a campaign actually leaves from (stage 3's From-address decision,
		// Memory/campaigns/marketing-growth/parts/M4.md) -- shown, not chosen, same as the sender itself.
		owner
			.from('communication_email_domains')
			.select('domain_name')
			.eq('organization_id', organizationId)
			.eq('purpose', 'marketing_sending')
			.eq('lifecycle_state', 'verified')
			.maybeSingle(),
		owner
			.from('organization_settings')
			.select('phone, website')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		owner
			.from('forms')
			.select('id, name, outcome, public_slug, current_published_version_id')
			.eq('organization_id', organizationId)
			.eq('is_enabled', true)
			.is('archived_at', null)
			.order('name'),
		owner.rpc('effective_marketing_email_limit', { target_organization_id: organizationId })
	]);

	for (const result of [domains, marketingDomain, settings, forms, allowance]) {
		if (result.error) throw result.error;
	}

	const domainIds = (domains.data ?? []).map((domain) => domain.id);
	// A derived address needs both an operational sender (for the display name and local part) and a
	// verified marketing domain (to send through) -- a campaign cannot leave without both, so showing a
	// real-looking address for only one half would be misleading.
	let sender: MarketingDeliverySender | null = null;
	if (domainIds.length > 0 && marketingDomain.data) {
		const senders = await owner
			.from('communication_email_senders')
			.select('id, email_address, display_name, is_organization_default')
			.eq('organization_id', organizationId)
			.eq('lifecycle_state', 'enabled')
			.in('domain_id', domainIds)
			.order('is_organization_default', { ascending: false })
			.order('created_at')
			.limit(1);
		if (senders.error) throw senders.error;
		const row = senders.data?.[0];
		if (row) {
			const localPart = row.email_address.split('@')[0];
			sender = {
				id: row.id,
				email_address: `${localPart}@${marketingDomain.data.domain_name}`,
				display_name: row.display_name
			};
		}
	}

	const publishedForms = (forms.data ?? []).filter((form) => form.current_published_version_id);
	const limitRow = allowance.data?.[0];

	return {
		sender,
		business_phone: settings.data?.phone ?? null,
		business_website: settings.data?.website ?? null,
		forms: publishedForms.map((form) => ({
			id: form.id,
			name: form.name,
			outcome: form.outcome,
			public_slug: form.public_slug
		})),
		allowance: {
			state: limitRow?.state ?? 'not_included',
			value: limitRow?.value ?? null,
			is_unlimited: limitRow?.is_unlimited ?? false
		}
	};
}
