import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const [
			packagesResult,
			versionsResult,
			featuresResult,
			versionFeaturesResult,
			versionLimitsResult
		] = await Promise.all([
			client
				.from('platform_packages')
				.select(
					'package_id, package_key, display_name, sort_order, status, public_description, price_usd_cents, currency, billing_period'
				)
				.order('sort_order', { ascending: true }),
			client
				.from('platform_package_versions')
				.select(
					'id, package_id, version_number, status, display_name, public_description, value_explanation, price_usd_cents, currency, billing_period, published_at, retired_at, created_at'
				)
				.order('created_at', { ascending: false }),
			client.from('features').select('feature_key, description').order('feature_key'),
			client
				.from('platform_package_version_features')
				.select('package_version_id, feature_key')
				.order('feature_key'),
			client
				.from('platform_package_version_limits')
				.select('package_version_id, limit_key, limit_state, limit_value')
		]);

		const results = [
			packagesResult,
			versionsResult,
			featuresResult,
			versionFeaturesResult,
			versionLimitsResult
		];
		const failed = results.find((result) => result.error);
		if (failed?.error) {
			console.error('Could not load owner package definitions.', failed.error);
			return json({ error: 'Package definitions could not be loaded.' }, { status: 500 });
		}

		const versions = (versionsResult.data ?? []).map((version) => ({
			...version,
			features: (versionFeaturesResult.data ?? [])
				.filter((feature) => feature.package_version_id === version.id)
				.map((feature) => feature.feature_key),
			limits: (versionLimitsResult.data ?? [])
				.filter((limit) => limit.package_version_id === version.id)
				.map(({ package_version_id: _packageVersionId, ...limit }) => limit)
		}));

		return json({
			packages: (packagesResult.data ?? []).map((packageDefinition) => ({
				...packageDefinition,
				versions: versions.filter((version) => version.package_id === packageDefinition.package_id)
			})),
			// `automation.workflows` is legacy: retired historical versions keep it, but new drafts must not be
			// able to assign it. `automations` is the live Automation feature.
			feature_catalog: (featuresResult.data ?? []).filter(
				(feature) => feature.feature_key !== 'automation.workflows'
			),
			limit_catalog: [{ limit_key: 'employee_seats', label: 'Employee seats' }]
		});
	} catch (error) {
		console.error('Owner package service is unavailable.', error);
		return json({ error: 'Package definitions could not be loaded.' }, { status: 503 });
	}
};
