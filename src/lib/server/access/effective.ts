import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Tables } from '$lib/database.types';

export type AccessClient = SupabaseClient<Database>;
export type PackageKey = 'starter' | 'growth' | 'elite';
export type LimitKey = 'employee_seats';

export const PACKAGE_ORDER: Record<PackageKey, number> = {
	starter: 1,
	growth: 2,
	elite: 3
};

export type OrganizationBilling = {
	paid_through_date: string | null;
	paid_through_source: string | null;
	grace_ends_at: string | null;
	is_overdue: boolean;
	is_in_grace: boolean;
};

export type EffectiveOrganizationAccess = {
	organization: Pick<Tables<'organizations'>, 'id' | 'name' | 'slug' | 'lifecycle_status'>;
	billing: OrganizationBilling;
	package: {
		current_key: PackageKey;
		effective_key: PackageKey;
		package_id: string;
		version_id: string | null;
		version_number: number | null;
		status: 'draft' | 'published' | 'retired';
		display_name: string;
		public_description: string | null;
		price_usd_cents: number | null;
		currency: string;
		billing_period: string;
		scheduled_key: PackageKey | null;
		scheduled_effective_at: string | null;
	};
	features: Record<string, boolean>;
	package_features: Record<string, boolean>;
	feature_overrides: Record<
		string,
		{ state: 'on' | 'off'; starts_at: string; expires_at: string | null }
	>;
	limits: Record<
		LimitKey,
		{ value: number | null; is_unlimited: boolean; source: 'package' | 'override' }
	>;
	limit_overrides: Partial<
		Record<
			LimitKey,
			{ value: number | null; is_unlimited: boolean; starts_at: string; expires_at: string | null }
		>
	>;
	member: { user_id: string; role: string } | null;
	permissions: Record<string, boolean>;
};

export class OrganizationAccessNotFoundError extends Error {
	constructor(message = 'Organization was not found.') {
		super(message);
		this.name = 'OrganizationAccessNotFoundError';
	}
}

const permissionFeaturePrefixes: Array<[string, string]> = [
	['customer.', 'core.customers_properties'],
	['customers.', 'core.customers_properties'],
	['property.', 'core.customers_properties'],
	['properties.', 'core.customers_properties'],
	['request.', 'core.requests_assessments'],
	['requests.', 'core.requests_assessments'],
	['pipeline.', 'sales.pipeline'],
	['quote.', 'core.quotes'],
	['quotes.', 'core.quotes'],
	['job.', 'core.jobs'],
	['jobs.', 'core.jobs'],
	['schedule.', 'core.schedule'],
	['invoice.', 'core.invoices_payments'],
	['invoices.', 'core.invoices_payments'],
	['payment.', 'core.invoices_payments'],
	['payments.', 'core.invoices_payments'],
	['inbox.', 'communications.inbox'],
	['portal.', 'portal.client'],
	['automation.', 'automation.workflows'],
	['report.', 'reporting.advanced'],
	['reports.', 'reporting.advanced'],
	['team.', 'core.team'],
	['settings.', 'core.team']
];

const GRACE_PERIOD_DAYS = 7;

function endOfUtcDay(date: string) {
	return new Date(`${date}T23:59:59.999Z`);
}

function computeBilling(
	row: { paid_through_date: string | null; paid_through_source: string | null } | null,
	now: number
): OrganizationBilling {
	const paidThroughDate = row?.paid_through_date ?? null;
	if (!paidThroughDate) {
		return {
			paid_through_date: null,
			paid_through_source: row?.paid_through_source ?? null,
			grace_ends_at: null,
			is_overdue: false,
			is_in_grace: false
		};
	}

	const paidThroughEnd = endOfUtcDay(paidThroughDate);
	const graceEndsAt = new Date(paidThroughEnd.getTime() + GRACE_PERIOD_DAYS * 24 * 60 * 60 * 1000);
	const isOverdue = now > paidThroughEnd.getTime();

	return {
		paid_through_date: paidThroughDate,
		paid_through_source: row?.paid_through_source ?? null,
		grace_ends_at: graceEndsAt.toISOString(),
		is_overdue: isOverdue,
		is_in_grace: isOverdue && now <= graceEndsAt.getTime()
	};
}

function packageKey(value: string): PackageKey {
	if (value === 'starter' || value === 'growth' || value === 'elite') return value;
	throw new Error(`Unsupported package key: ${value}`);
}

function isActiveWindow(row: { starts_at: string; expires_at: string | null }, now: number) {
	const startsAt = Date.parse(row.starts_at);
	const expiresAt = row.expires_at ? Date.parse(row.expires_at) : null;
	return startsAt <= now && (expiresAt === null || expiresAt > now);
}

function buildFeatureOverridesMap(
	featureOverrides: Array<{
		feature_key: string;
		override_state: string;
		starts_at: string;
		expires_at: string | null;
	}>
): EffectiveOrganizationAccess['feature_overrides'] {
	return Object.fromEntries(
		featureOverrides.map((item) => [
			item.feature_key,
			{
				state: item.override_state as 'on' | 'off',
				starts_at: item.starts_at,
				expires_at: item.expires_at
			}
		])
	);
}

function buildLimitOverridesMap(
	limitOverrides: Array<{
		limit_key: string;
		limit_value: number | null;
		is_unlimited: boolean;
		starts_at: string;
		expires_at: string | null;
	}>
): EffectiveOrganizationAccess['limit_overrides'] {
	return Object.fromEntries(
		limitOverrides.map((item) => [
			item.limit_key,
			{
				value: item.limit_value,
				is_unlimited: item.is_unlimited,
				starts_at: item.starts_at,
				expires_at: item.expires_at
			}
		])
	) as EffectiveOrganizationAccess['limit_overrides'];
}

function featureForPermission(permissionKey: string) {
	return (
		permissionFeaturePrefixes.find(([prefix]) => permissionKey.startsWith(prefix))?.[1] ?? null
	);
}

export function permissionIsEnabled(permissionKey: string, features: Record<string, boolean>) {
	const featureKey = featureForPermission(permissionKey);
	return featureKey ? features[featureKey] === true : true;
}

async function resolveLegacyOrganizationAccess(
	client: AccessClient,
	organizationId: string,
	userId?: string,
	now = new Date()
): Promise<EffectiveOrganizationAccess> {
	const { data: organization, error: organizationError } = await client
		.from('organizations')
		.select(
			'id, name, slug, lifecycle_status, package_key, scheduled_package_key, scheduled_package_effective_at'
		)
		.eq('id', organizationId)
		.maybeSingle();
	if (organizationError) throw organizationError;
	if (!organization) throw new OrganizationAccessNotFoundError();

	const [
		packagesResult,
		featuresResult,
		packageFeaturesResult,
		packageLimitsResult,
		featureOverridesResult,
		limitOverridesResult,
		billingResult
	] = await Promise.all([
		client
			.from('platform_packages')
			.select(
				'package_id, package_key, display_name, sort_order, status, public_description, price_usd_cents, currency, billing_period'
			),
		client.from('features').select('feature_key, description'),
		client.from('package_features').select('package_key, feature_key'),
		client.from('package_limits').select('package_key, limit_key, limit_value, is_unlimited'),
		client
			.from('organization_feature_overrides')
			.select('feature_key, override_state, starts_at, expires_at')
			.eq('organization_id', organizationId),
		client
			.from('organization_limit_overrides')
			.select('limit_key, limit_value, is_unlimited, starts_at, expires_at')
			.eq('organization_id', organizationId),
		client
			.from('organization_billing_accounts')
			.select('paid_through_date, paid_through_source')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);

	const queryResults = [
		packagesResult,
		featuresResult,
		packageFeaturesResult,
		packageLimitsResult,
		featureOverridesResult,
		limitOverridesResult,
		billingResult
	];
	const failedQuery = queryResults.find((result) => result.error);
	if (failedQuery?.error) throw failedQuery.error;

	const packages = packagesResult.data ?? [];
	const currentPackageKey = packageKey(organization.package_key);
	const scheduledPackageKey = organization.scheduled_package_key
		? packageKey(organization.scheduled_package_key)
		: null;
	const scheduledAt = organization.scheduled_package_effective_at;
	const scheduledIsDue =
		scheduledPackageKey !== null &&
		scheduledAt !== null &&
		Date.parse(scheduledAt) <= now.getTime();
	const effectivePackageKey = scheduledIsDue ? scheduledPackageKey : currentPackageKey;
	const effectivePackage = packages.find((item) => item.package_key === effectivePackageKey);
	if (!effectivePackage) throw new Error(`Package definition is missing: ${effectivePackageKey}`);

	const featureRows = featuresResult.data ?? [];
	const packageFeatureKeys = new Set(
		(packageFeaturesResult.data ?? [])
			.filter((item) => item.package_key === effectivePackageKey)
			.map((item) => item.feature_key)
	);
	const nowMs = now.getTime();
	const featureOverrides = (featureOverridesResult.data ?? []).filter((item) =>
		isActiveWindow(item, nowMs)
	);
	const featureOverrideByKey = new Map(featureOverrides.map((item) => [item.feature_key, item]));
	const packageFeatureFlags = Object.fromEntries(
		featureRows.map((feature) => [feature.feature_key, packageFeatureKeys.has(feature.feature_key)])
	);
	const featureFlags = Object.fromEntries(
		featureRows.map((feature) => {
			const override = featureOverrideByKey.get(feature.feature_key);
			return [
				feature.feature_key,
				override ? override.override_state === 'on' : packageFeatureKeys.has(feature.feature_key)
			];
		})
	);

	const packageLimitByKey = new Map(
		(packageLimitsResult.data ?? [])
			.filter((item) => item.package_key === effectivePackageKey)
			.map((item) => [item.limit_key, item])
	);
	const limitOverrides = (limitOverridesResult.data ?? []).filter((item) =>
		isActiveWindow(item, nowMs)
	);
	const limitOverrideByKey = new Map(limitOverrides.map((item) => [item.limit_key, item]));
	const employeeSeatLimit =
		limitOverrideByKey.get('employee_seats') ?? packageLimitByKey.get('employee_seats');
	const limits = {
		employee_seats: {
			value: employeeSeatLimit?.limit_value ?? null,
			is_unlimited: employeeSeatLimit?.is_unlimited ?? false,
			source: limitOverrideByKey.has('employee_seats')
				? ('override' as const)
				: ('package' as const)
		}
	};

	let member: EffectiveOrganizationAccess['member'] = null;
	let permissions: Record<string, boolean> = {};
	if (userId) {
		const { data: membership, error: membershipError } = await client
			.from('organization_members')
			.select('user_id, role')
			.eq('organization_id', organizationId)
			.eq('user_id', userId)
			.maybeSingle();
		if (membershipError) throw membershipError;
		if (!membership)
			throw new OrganizationAccessNotFoundError('Organization membership was not found.');
		member = membership;

		const [rolePermissionsResult, memberOverridesResult] = await Promise.all([
			client.from('role_permissions').select('permission_key').eq('role', membership.role),
			client
				.from('organization_member_permission_overrides')
				.select('permission_key, override_state')
				.eq('organization_id', organizationId)
				.eq('user_id', userId)
		]);
		if (rolePermissionsResult.error) throw rolePermissionsResult.error;
		if (memberOverridesResult.error) throw memberOverridesResult.error;

		const resolvedPermissions = new Map(
			(rolePermissionsResult.data ?? []).map((item) => [item.permission_key, true])
		);
		for (const override of memberOverridesResult.data ?? []) {
			resolvedPermissions.set(override.permission_key, override.override_state === 'grant');
		}
		permissions = Object.fromEntries(
			[...resolvedPermissions.entries()].map(([permissionKey, enabled]) => [
				permissionKey,
				enabled && permissionIsEnabled(permissionKey, featureFlags)
			])
		);
	}

	return {
		organization: {
			id: organization.id,
			name: organization.name,
			slug: organization.slug,
			lifecycle_status: organization.lifecycle_status
		},
		billing: computeBilling(billingResult.data ?? null, now.getTime()),
		package: {
			current_key: currentPackageKey,
			effective_key: effectivePackageKey,
			package_id: effectivePackage.package_id,
			version_id: null,
			version_number: null,
			status: effectivePackage.status as 'draft' | 'published' | 'retired',
			display_name: effectivePackage.display_name,
			public_description: effectivePackage.public_description,
			price_usd_cents: effectivePackage.price_usd_cents,
			currency: effectivePackage.currency,
			billing_period: effectivePackage.billing_period,
			scheduled_key: scheduledPackageKey,
			scheduled_effective_at: scheduledAt
		},
		features: featureFlags,
		package_features: packageFeatureFlags,
		feature_overrides: buildFeatureOverridesMap(featureOverrides),
		limits,
		limit_overrides: buildLimitOverridesMap(limitOverrides),
		member,
		permissions
	};
}

type OrganizationRow = {
	id: string;
	name: string;
	slug: string;
	lifecycle_status: string;
	package_key: string;
	scheduled_package_key: string | null;
	scheduled_package_effective_at: string | null;
};

async function resolveVersionedOrganizationAccess(
	client: AccessClient,
	organization: OrganizationRow,
	assignment: { package_version_id: string },
	userId?: string,
	now = new Date()
): Promise<EffectiveOrganizationAccess> {
	const [
		versionResult,
		featuresResult,
		packageFeaturesResult,
		packageLimitsResult,
		featureOverridesResult,
		limitOverridesResult,
		billingResult
	] = await Promise.all([
		client
			.from('platform_package_versions')
			.select(
				'id, package_id, version_number, display_name, public_description, price_usd_cents, currency, billing_period, status'
			)
			.eq('id', assignment.package_version_id)
			.maybeSingle(),
		client.from('features').select('feature_key, description'),
		client
			.from('platform_package_version_features')
			.select('package_version_id, feature_key')
			.eq('package_version_id', assignment.package_version_id),
		client
			.from('platform_package_version_limits')
			.select('package_version_id, limit_key, limit_state, limit_value')
			.eq('package_version_id', assignment.package_version_id),
		client
			.from('organization_feature_overrides')
			.select('feature_key, override_state, starts_at, expires_at')
			.eq('organization_id', organization.id),
		client
			.from('organization_limit_overrides')
			.select('limit_key, limit_value, is_unlimited, starts_at, expires_at')
			.eq('organization_id', organization.id),
		client
			.from('organization_billing_accounts')
			.select('paid_through_date, paid_through_source')
			.eq('organization_id', organization.id)
			.maybeSingle()
	]);

	const queryResults = [
		versionResult,
		featuresResult,
		packageFeaturesResult,
		packageLimitsResult,
		featureOverridesResult,
		limitOverridesResult,
		billingResult
	];
	const failedQuery = queryResults.find((result) => result.error);
	if (failedQuery?.error) throw failedQuery.error;
	if (!versionResult.data) throw new Error('The organization package version is missing.');
	const packageResult = await client
		.from('platform_packages')
		.select('package_id, package_key')
		.eq('package_id', versionResult.data.package_id);
	if (packageResult.error) throw packageResult.error;
	const packageDefinition = (packageResult.data ?? [])[0];
	if (!packageDefinition) throw new Error('The organization package definition is missing.');

	const currentPackageKey = packageKey(packageDefinition.package_key);
	const nowMs = now.getTime();
	const featureOverrides = (featureOverridesResult.data ?? []).filter((item) =>
		isActiveWindow(item, nowMs)
	);
	const featureOverrideByKey = new Map(featureOverrides.map((item) => [item.feature_key, item]));
	const packageFeatureKeys = new Set(
		(packageFeaturesResult.data ?? []).map((item) => item.feature_key)
	);
	const packageFeatureFlags = Object.fromEntries(
		(featuresResult.data ?? []).map((feature) => [
			feature.feature_key,
			packageFeatureKeys.has(feature.feature_key)
		])
	);
	const features = Object.fromEntries(
		(featuresResult.data ?? []).map((feature) => {
			const override = featureOverrideByKey.get(feature.feature_key);
			return [
				feature.feature_key,
				override ? override.override_state === 'on' : packageFeatureKeys.has(feature.feature_key)
			];
		})
	);

	const limitOverrides = (limitOverridesResult.data ?? []).filter((item) =>
		isActiveWindow(item, nowMs)
	);
	const limitOverride = limitOverrides.find((item) => item.limit_key === 'employee_seats');
	const packageLimit = (packageLimitsResult.data ?? []).find(
		(item) => item.limit_key === 'employee_seats'
	);
	const limits = {
		employee_seats: {
			value: limitOverride
				? limitOverride.limit_value
				: packageLimit?.limit_state === 'numeric'
					? packageLimit.limit_value
					: null,
			is_unlimited: limitOverride
				? limitOverride.is_unlimited
				: packageLimit?.limit_state === 'unlimited',
			source: limitOverride ? ('override' as const) : ('package' as const)
		}
	};

	let member: EffectiveOrganizationAccess['member'] = null;
	let permissions: Record<string, boolean> = {};
	if (userId) {
		const { data: membership, error: membershipError } = await client
			.from('organization_members')
			.select('user_id, role')
			.eq('organization_id', organization.id)
			.eq('user_id', userId)
			.maybeSingle();
		if (membershipError) throw membershipError;
		if (!membership)
			throw new OrganizationAccessNotFoundError('Organization membership was not found.');
		member = membership;

		const [rolePermissionsResult, memberOverridesResult] = await Promise.all([
			client.from('role_permissions').select('permission_key').eq('role', membership.role),
			client
				.from('organization_member_permission_overrides')
				.select('permission_key, override_state')
				.eq('organization_id', organization.id)
				.eq('user_id', userId)
		]);
		if (rolePermissionsResult.error) throw rolePermissionsResult.error;
		if (memberOverridesResult.error) throw memberOverridesResult.error;

		const resolvedPermissions = new Map(
			(rolePermissionsResult.data ?? []).map((item) => [item.permission_key, true])
		);
		for (const override of memberOverridesResult.data ?? []) {
			resolvedPermissions.set(override.permission_key, override.override_state === 'grant');
		}
		permissions = Object.fromEntries(
			[...resolvedPermissions.entries()].map(([permissionKey, enabled]) => [
				permissionKey,
				enabled && permissionIsEnabled(permissionKey, features)
			])
		);
	}

	return {
		organization: {
			id: organization.id,
			name: organization.name,
			slug: organization.slug,
			lifecycle_status: organization.lifecycle_status
		},
		billing: computeBilling(billingResult.data ?? null, now.getTime()),
		package: {
			current_key: currentPackageKey,
			effective_key: currentPackageKey,
			package_id: packageDefinition.package_id,
			version_id: versionResult.data.id,
			version_number: versionResult.data.version_number,
			status: versionResult.data.status as 'draft' | 'published' | 'retired',
			display_name: versionResult.data.display_name,
			public_description: versionResult.data.public_description,
			price_usd_cents: versionResult.data.price_usd_cents,
			currency: versionResult.data.currency,
			billing_period: versionResult.data.billing_period,
			scheduled_key: null,
			scheduled_effective_at: null
		},
		features,
		package_features: packageFeatureFlags,
		feature_overrides: buildFeatureOverridesMap(featureOverrides),
		limits,
		limit_overrides: buildLimitOverridesMap(limitOverrides),
		member,
		permissions
	};
}

export async function resolveOrganizationAccess(
	client: AccessClient,
	organizationId: string,
	userId?: string,
	now = new Date()
): Promise<EffectiveOrganizationAccess> {
	const { data: organization, error: organizationError } = await client
		.from('organizations')
		.select(
			'id, name, slug, lifecycle_status, package_key, scheduled_package_key, scheduled_package_effective_at'
		)
		.eq('id', organizationId)
		.maybeSingle();
	if (organizationError) throw organizationError;
	if (!organization) throw new OrganizationAccessNotFoundError();

	const { data: assignment, error: assignmentError } = await client
		.from('organization_package_assignments')
		.select('package_version_id, effective_at')
		.eq('organization_id', organizationId)
		.order('effective_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (assignmentError) throw assignmentError;

	if (assignment) {
		return resolveVersionedOrganizationAccess(client, organization, assignment, userId, now);
	}

	return resolveLegacyOrganizationAccess(client, organizationId, userId, now);
}
