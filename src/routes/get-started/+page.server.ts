import { env as publicEnv } from '$env/dynamic/public';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async () => {
	const client = getOwnerSupabaseClient();

	// Public, published, unarchived editions only. The cards are rebuilt in package-builder P9; until then
	// each edition offers its monthly price when it has one, otherwise its yearly price.
	const [editionsResult, settings] = await Promise.all([
		client
			.from('package_editions')
			.select(
				`id, name, promise, highlights, monthly_price_usd_cents, yearly_price_usd_cents,
				packages!inner(visibility, archived_at, display_order),
				package_edition_allowances(allowance_key, allowance_state, allowance_value)`
			)
			.eq('status', 'published')
			.eq('packages.visibility', 'public')
			.is('packages.archived_at', null),
		getOrCreateOwnerSettings(client)
	]);
	if (editionsResult.error) throw editionsResult.error;

	const packages = editionsResult.data
		.flatMap((edition) => {
			const billingInterval =
				edition.monthly_price_usd_cents !== null
					? ('month' as const)
					: edition.yearly_price_usd_cents !== null
						? ('year' as const)
						: null;
			if (!billingInterval) return [];
			const seats = edition.package_edition_allowances.find(
				(allowance) => allowance.allowance_key === 'employee_seats'
			);
			return [
				{
					package_edition_id: edition.id,
					billing_interval: billingInterval,
					display_name: edition.name,
					public_description: edition.promise ?? '',
					price_usd_cents:
						(billingInterval === 'month'
							? edition.monthly_price_usd_cents
							: edition.yearly_price_usd_cents) ?? 0,
					sort_order: edition.packages.display_order,
					features: (Array.isArray(edition.highlights) ? edition.highlights : []).filter(
						(highlight): highlight is string => typeof highlight === 'string'
					),
					seat_limit: seats
						? { limit_state: seats.allowance_state, limit_value: seats.allowance_value }
						: undefined
				}
			];
		})
		.sort((a, b) => a.sort_order - b.sort_order);

	return {
		packages,
		privacyPolicyUrl: settings.privacy_policy_url,
		privacyPolicyVersion: settings.privacy_policy_version,
		turnstileSiteKey: publicEnv.PUBLIC_TURNSTILE_SITE_KEY ?? ''
	};
};
