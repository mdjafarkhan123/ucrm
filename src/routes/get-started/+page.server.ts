import { env as publicEnv } from '$env/dynamic/public';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async () => {
	const client = getOwnerSupabaseClient();

	const [versionsResult, settings] = await Promise.all([
		client
			.from('platform_package_versions')
			.select(
				`id, display_name, public_description, value_explanation, price_usd_cents, currency,
				billing_period,
				platform_packages!inner(status, sort_order),
				platform_package_version_features(features(description)),
				platform_package_version_limits(limit_key, limit_state, limit_value)`
			)
			.eq('status', 'published')
			.eq('platform_packages.status', 'published'),
		getOrCreateOwnerSettings(client)
	]);
	if (versionsResult.error) throw versionsResult.error;

	const packages = versionsResult.data
		.map((version) => ({
			package_version_id: version.id,
			display_name: version.display_name,
			public_description: version.public_description ?? '',
			value_explanation: version.value_explanation ?? '',
			price_usd_cents: version.price_usd_cents ?? 0,
			currency: version.currency,
			billing_period: version.billing_period,
			sort_order: version.platform_packages.sort_order,
			features: version.platform_package_version_features
				.map((row) => row.features?.description)
				.filter((description): description is string => Boolean(description)),
			seat_limit: version.platform_package_version_limits.find(
				(limit) => limit.limit_key === 'employee_seats'
			)
		}))
		.sort((a, b) => a.sort_order - b.sort_order);

	return {
		packages,
		privacyPolicyUrl: settings.privacy_policy_url,
		privacyPolicyVersion: settings.privacy_policy_version,
		turnstileSiteKey: publicEnv.PUBLIC_TURNSTILE_SITE_KEY ?? ''
	};
};
