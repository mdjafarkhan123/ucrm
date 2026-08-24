import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Tables } from '$lib/database.types';

export type AccessClient = SupabaseClient<Database>;
export type PackageKey = 'starter' | 'growth' | 'elite';
export type LimitKey = 'employee_seats';
export type LimitState = 'unlimited' | 'not_included' | 'numeric';

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

export type FreeAccessGrant = {
	grant_id: string;
	starts_at: string;
	access_until_date: string | null;
};

export type FreeAccessState = {
	active: FreeAccessGrant | null;
	future: FreeAccessGrant | null;
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
		{
			state: 'on' | 'off';
			starts_at: string;
			expires_at: string | null;
			reason: string | null;
			is_legacy_import: boolean;
		}
	>;
	limits: Record<
		LimitKey,
		{
			state: LimitState;
			value: number | null;
			is_unlimited: boolean;
			source: 'package' | 'override';
		}
	>;
	limit_overrides: Partial<
		Record<
			LimitKey,
			{
				state: LimitState;
				value: number | null;
				is_unlimited: boolean;
				starts_at: string;
				expires_at: string | null;
			}
		>
	>;
	member: { user_id: string; role: string } | null;
	permissions: Record<string, boolean>;
	free_access: FreeAccessState;
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
	// The price list only exists to be quoted from, so it rides on the same entitlement as quotes.
	['catalog.', 'core.quotes'],
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
	['team.', 'core.team']
];

function todayInTimeZone(timezone: string, now: Date) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(now);
}

function computeCommercialBilling(
	row: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
	} | null,
	commercialTimezone: string | null,
	now: Date,
	hasActiveFreeAccess: boolean
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

	if (hasActiveFreeAccess) {
		return {
			paid_through_date: paidThroughDate,
			paid_through_source: row?.paid_through_source ?? null,
			grace_ends_at: row?.grace_ends_at ?? null,
			is_overdue: false,
			is_in_grace: false
		};
	}

	const isOverdue = todayInTimeZone(commercialTimezone ?? 'UTC', now) > paidThroughDate;
	const graceEndsAt = row?.grace_ends_at ?? null;

	return {
		paid_through_date: paidThroughDate,
		paid_through_source: row?.paid_through_source ?? null,
		grace_ends_at: graceEndsAt,
		is_overdue: isOverdue,
		is_in_grace:
			isOverdue && graceEndsAt !== null && now.getTime() <= new Date(graceEndsAt).getTime()
	};
}

function computeFreeAccessState(
	events: Array<{
		id: string;
		target_grant_id: string | null;
		action: string;
		starts_at: string;
		access_until_date: string | null;
		occurred_at: string;
	}>,
	todayDate: string
): FreeAccessState {
	const roots = new Map<string, typeof events>();
	for (const event of events) {
		const rootId = event.target_grant_id ?? event.id;
		const group = roots.get(rootId);
		if (group) group.push(event);
		else roots.set(rootId, [event]);
	}

	let active: FreeAccessGrant | null = null;
	let future: FreeAccessGrant | null = null;
	for (const [rootId, group] of roots) {
		const latest = [...group].sort(
			(a, b) => Date.parse(b.occurred_at) - Date.parse(a.occurred_at)
		)[0];
		if (latest.action === 'end') continue;
		const rootEvent = group.find((item) => item.target_grant_id === null);
		if (!rootEvent) continue;

		const grant: FreeAccessGrant = {
			grant_id: rootId,
			starts_at: rootEvent.starts_at,
			access_until_date: latest.access_until_date
		};
		if (
			rootEvent.starts_at <= todayDate &&
			(grant.access_until_date === null || grant.access_until_date >= todayDate)
		) {
			active = grant;
		} else if (rootEvent.starts_at > todayDate) {
			future = grant;
		}
	}

	return { active, future };
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
		reason?: string | null;
		is_legacy_import?: boolean;
	}>
): EffectiveOrganizationAccess['feature_overrides'] {
	return Object.fromEntries(
		featureOverrides.map((item) => [
			item.feature_key,
			{
				state: item.override_state as 'on' | 'off',
				starts_at: item.starts_at,
				expires_at: item.expires_at,
				reason: item.reason ?? null,
				is_legacy_import: item.is_legacy_import ?? true
			}
		])
	);
}

function buildLimitOverridesMap(
	limitOverrides: Array<{
		limit_key: string;
		limit_state?: string;
		limit_value: number | null;
		is_unlimited: boolean;
		starts_at: string;
		expires_at: string | null;
		reason?: string | null;
		is_legacy_import?: boolean;
	}>
): EffectiveOrganizationAccess['limit_overrides'] {
	return Object.fromEntries(
		limitOverrides.map((item) => [
			item.limit_key,
			{
				value: item.limit_value,
				is_unlimited: item.is_unlimited,
				state:
					(item.limit_state as LimitState | undefined) ??
					(item.is_unlimited
						? 'unlimited'
						: item.limit_value === null
							? 'not_included'
							: 'numeric'),
				starts_at: item.starts_at,
				expires_at: item.expires_at,
				reason: item.reason ?? null,
				is_legacy_import: item.is_legacy_import ?? true
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
		featureOverridesResult,
		limitOverridesResult,
		commercialStateResult,
		commercialSettingsResult,
		freeAccessEventsResult,
		seatLimitResult
	] = await Promise.all([
		client
			.from('platform_packages')
			.select(
				'package_id, package_key, display_name, sort_order, status, public_description, price_usd_cents, currency, billing_period'
			),
		client.from('features').select('feature_key, description'),
		client.from('package_features').select('package_key, feature_key'),
		client
			.from('organization_feature_overrides')
			.select('feature_key, override_state, starts_at, expires_at, reason, is_legacy_import')
			.eq('organization_id', organizationId),
		client
			.from('organization_limit_overrides')
			.select('limit_key, limit_state, limit_value, is_unlimited, starts_at, expires_at')
			.eq('organization_id', organizationId),
		client
			.from('organization_commercial_state')
			.select('paid_through_date, paid_through_source, grace_ends_at')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_commercial_settings')
			.select('commercial_timezone')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_free_access_events')
			.select('id, target_grant_id, action, starts_at, access_until_date, occurred_at')
			.eq('organization_id', organizationId),
		client.rpc('effective_employee_seat_limit', {
			target_organization_id: organizationId,
			at: now.toISOString()
		})
	]);

	const queryResults = [
		packagesResult,
		featuresResult,
		packageFeaturesResult,
		featureOverridesResult,
		limitOverridesResult,
		commercialStateResult,
		commercialSettingsResult,
		freeAccessEventsResult,
		seatLimitResult
	];
	const failedQuery = queryResults.find((result) => result.error);
	if (failedQuery?.error) throw failedQuery.error;
	const seatLimit = seatLimitResult.data?.[0];
	if (!seatLimit) throw new Error('The employee seat limit could not be resolved.');

	const commercialTimezone = commercialSettingsResult.data?.commercial_timezone ?? null;
	const freeAccessState = computeFreeAccessState(
		freeAccessEventsResult.data ?? [],
		todayInTimeZone(commercialTimezone ?? 'UTC', now)
	);

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

	const limitOverrides = (limitOverridesResult.data ?? []).filter((item) =>
		isActiveWindow(item, nowMs)
	);
	const limits = {
		employee_seats: {
			value: seatLimit.value,
			is_unlimited: seatLimit.is_unlimited,
			state: seatLimit.state as LimitState,
			source: seatLimit.source as 'package' | 'override'
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
		billing: computeCommercialBilling(
			commercialStateResult.data ?? null,
			commercialTimezone,
			now,
			freeAccessState.active !== null
		),
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
		permissions,
		free_access: freeAccessState
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
		featureOverridesResult,
		limitOverridesResult,
		commercialStateResult,
		commercialSettingsResult,
		freeAccessEventsResult,
		seatLimitResult
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
			.from('organization_feature_overrides')
			.select('feature_key, override_state, starts_at, expires_at, reason, is_legacy_import')
			.eq('organization_id', organization.id),
		client
			.from('organization_limit_overrides')
			.select('limit_key, limit_state, limit_value, is_unlimited, starts_at, expires_at')
			.eq('organization_id', organization.id),
		client
			.from('organization_commercial_state')
			.select('paid_through_date, paid_through_source, grace_ends_at')
			.eq('organization_id', organization.id)
			.maybeSingle(),
		client
			.from('organization_commercial_settings')
			.select('commercial_timezone')
			.eq('organization_id', organization.id)
			.maybeSingle(),
		client
			.from('organization_free_access_events')
			.select('id, target_grant_id, action, starts_at, access_until_date, occurred_at')
			.eq('organization_id', organization.id),
		client.rpc('effective_employee_seat_limit', {
			target_organization_id: organization.id,
			at: now.toISOString()
		})
	]);

	const queryResults = [
		versionResult,
		featuresResult,
		packageFeaturesResult,
		featureOverridesResult,
		limitOverridesResult,
		commercialStateResult,
		commercialSettingsResult,
		freeAccessEventsResult,
		seatLimitResult
	];
	const failedQuery = queryResults.find((result) => result.error);
	if (failedQuery?.error) throw failedQuery.error;
	if (!versionResult.data) throw new Error('The organization package version is missing.');
	const seatLimit = seatLimitResult.data?.[0];
	if (!seatLimit) throw new Error('The employee seat limit could not be resolved.');

	const commercialTimezone = commercialSettingsResult.data?.commercial_timezone ?? null;
	const freeAccessState = computeFreeAccessState(
		freeAccessEventsResult.data ?? [],
		todayInTimeZone(commercialTimezone ?? 'UTC', now)
	);
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
	const limits = {
		employee_seats: {
			value: seatLimit.value,
			is_unlimited: seatLimit.is_unlimited,
			state: seatLimit.state as LimitState,
			source: seatLimit.source as 'package' | 'override'
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
		billing: computeCommercialBilling(
			commercialStateResult.data ?? null,
			commercialTimezone,
			now,
			freeAccessState.active !== null
		),
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
		permissions,
		free_access: freeAccessState
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
